import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PithCore

@MainActor
struct InsertionTarget {
    let application: NSRunningApplication
    fileprivate let focusedElement: AXUIElement
    /// Ordinary dictation captures range metadata only; Ask also verifies its explicit selection.
    fileprivate let selectedTextRange: TextSelectionRange?
    fileprivate var expectedSelectedText: String? = nil
}

enum InsertionOutcome {
    /// A paste shortcut was sent; the receiving application does not acknowledge insertion.
    case sent
    case unavailable(String)
}

@MainActor
enum PasteboardInserter {
    /// Captures identity and role only, never the contents of the focused field.
    static func captureTarget(_ app: NSRunningApplication?) -> InsertionTarget? {
        guard AXIsProcessTrusted(), let app,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let element = focusedElement(in: app),
              isTextInput(element) else { return nil }
        return InsertionTarget(
            application: app,
            focusedElement: element,
            selectedTextRange: selectedTextRange(in: element)
        )
    }

    /// Reads only the explicit selection for Ask; never copies the whole field or the clipboard.
    static func captureAsk(_ app: NSRunningApplication?) throws -> (target: InsertionTarget?, context: AskContext) {
        guard AXIsProcessTrusted(), let app, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !ContextPolicy.shouldBlock(bundleIdentifier: app.bundleIdentifier),
              let element = focusedElement(in: app), !isSecure(element) else {
            return (nil, AskContext())
        }
        let range = selectedTextRange(in: element)
        let text = selectedText(in: element).flatMap { $0.isEmpty ? nil : $0 }
        let editable = isTextInput(element)
        let canReplace = editable && text != nil && range?.length == text?.utf16.count
        let context = AskContext(selectedText: text, canInsert: editable && range?.length == 0,
                                 canReplaceSelection: canReplace)
        try context.validate()
        let target = editable ? InsertionTarget(application: app, focusedElement: element,
                                                selectedTextRange: range,
                                                expectedSelectedText: canReplace ? text : nil) : nil
        return (target, context)
    }

    /// Sends paste only while the captured input remains the current input target.
    static func insert(
        _ text: String,
        into target: InsertionTarget,
        automatically: Bool
    ) async -> InsertionOutcome {
        guard !Task.isCancelled else { return .unavailable("已取消插入，文本已保留。") }
        guard !text.isEmpty else { return .unavailable("没有可插入的文本。") }
        guard AXIsProcessTrusted() else {
            return .unavailable("未获得辅助功能权限，文本已保留，可手动复制。")
        }
        let application = target.application
        guard !application.isTerminated else {
            return .unavailable("原应用已退出，文本已保留，可手动复制。")
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return .unavailable("无法确认当前输入位置，文本已保留，可手动复制。")
        }
        if frontmost.processIdentifier != application.processIdentifier {
            let pithProcessID = ProcessInfo.processInfo.processIdentifier
            guard !automatically || frontmost.processIdentifier == pithProcessID else {
                return .unavailable("你已切换到其他应用，文本已保留，可手动复制。")
            }
            guard application.activate(options: [.activateAllWindows]) else {
                return .unavailable("无法返回原应用，文本已保留，可手动复制。")
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                return .unavailable("已取消插入，文本已保留。")
            } catch {
                return .unavailable("无法等待原应用就绪，文本已保留，可手动复制。")
            }
        }

        guard !Task.isCancelled else { return .unavailable("已取消插入，文本已保留。") }
        guard targetIsFocused(target, verifySelection: automatically) else {
            return .unavailable("输入位置已改变，文本已保留，可手动复制。")
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .unavailable("无法发送粘贴快捷键，文本已保留，可手动复制。")
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        guard let previousItems = copyItems(from: pasteboard) else {
            return .unavailable("无法完整保留当前剪贴板，文本已保留，可手动复制。")
        }
        guard pasteboard.changeCount == previousChangeCount,
              !Task.isCancelled, targetIsFocused(target, verifySelection: automatically) else {
            return .unavailable("输入位置或剪贴板已改变，文本已保留，可手动复制。")
        }
        let clearedChangeCount = pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard, ifUnchangedSince: clearedChangeCount)
            return .unavailable("无法写入剪贴板，文本已保留，可重试复制。")
        }
        let insertionChangeCount = pasteboard.changeCount
        guard !Task.isCancelled, targetIsFocused(target, verifySelection: automatically),
              pasteboard.changeCount == insertionChangeCount else {
            restore(previousItems, to: pasteboard, ifUnchangedSince: insertionChangeCount)
            return .unavailable("输入位置已改变或插入已取消，文本已保留。")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Restoration survives cancellation after Cmd-V so the temporary clipboard
        // remains available while the receiving application consumes the paste.
        await Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            restore(previousItems, to: pasteboard, ifUnchangedSince: insertionChangeCount)
        }.value
        return .sent
    }

    private static func targetIsFocused(_ target: InsertionTarget, verifySelection: Bool) -> Bool {
        guard AXIsProcessTrusted(), !target.application.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier,
              let current = focusedElement(in: target.application),
              isTextInput(current) else { return false }
        guard CFEqual(current, target.focusedElement) else { return false }
        if let expected = target.expectedSelectedText, selectedText(in: current) != expected { return false }
        return InsertionSafety.selectionMatches(
            original: target.selectedTextRange,
            current: selectedTextRange(in: current),
            automatic: verifySelection || target.expectedSelectedText != nil,
            requiresKnownRange: target.expectedSelectedText != nil
        )
    }

    private static func focusedElement(in application: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func isTextInput(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String, !isSecure(element) else { return false }
        var enabled: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        if (enabled as? Bool) == false { return false }
        var editable: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editable)
        if let editable = editable as? Bool { return editable }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return false }
        var valueSettable = DarwinBoolean(false)
        var selectionSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectionSettable)
        return valueSettable.boolValue || selectionSettable.boolValue
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == kAXSecureTextFieldSubrole
    }

    private static func selectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedTextRange(in element: AXUIElement) -> TextSelectionRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return TextSelectionRange(location: range.location, length: range.length)
    }

    private static func copyItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        var copies: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else {
                    return nil
                }
            }
            copies.append(copy)
        }
        return copies
    }

    private static func restore(
        _ items: [NSPasteboardItem],
        to pasteboard: NSPasteboard,
        ifUnchangedSince changeCount: Int
    ) {
        // Never overwrite a copy action performed while transcription was being pasted.
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
