import AppKit
import PithCore
import SwiftUI

@main
@MainActor
struct PithApplication: App {
    @NSApplicationDelegateAdaptor(PithAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { SettingsView(model: appDelegate.model) }
    }
}

@MainActor
final class PithAppDelegate: NSObject, NSApplicationDelegate {
    let model = PithAppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var libraryWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var voicePanel: VoicePanel?
    private var shortcutHintPanel: VoicePanel?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: MenuBarView(
            model: model,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenLibrary: { [weak self] in self?.openLibrary() },
            onOpenEditor: { [weak self] in self?.openEditor() }
        ))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 350, height: 400)
        model.onSessionChange = { [weak self] in self?.updateSessionPresentation() }
        model.onShortcutHintChange = { [weak self] visible in self?.showShortcutHint(visible) }
        model.onRecordingWillStart = { [weak self] in
            self?.popover.performClose(nil)
            self?.settingsWindow?.orderOut(nil)
            self?.libraryWindow?.orderOut(nil)
            self?.editorWindow?.orderOut(nil)
        }
        model.onDraftNeedsAttention = { [weak self] in self?.openEditor() }
        updateSessionPresentation()
        model.installGlobalShortcuts()
        if !model.apiKeyIsConfigured || (model.configuration.transcriptionSource == .system && !model.speechAuthorized) {
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Activating a visible editor should not cover it with the settings window.
        guard !flag else { return true }
        if model.draft != nil { openEditor() }
        else { openSettings() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        showShortcutHint(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        model.shutdown()
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.prepareForPopover()
            model.refreshReadiness()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateSessionPresentation() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        let symbol: String
        switch model.phase {
        case .recording: symbol = "mic.fill"
        case .requestingPermission, .processing, .inserting: symbol = "ellipsis.circle"
        case .failed: symbol = "exclamationmark.circle"
        case .idle, .completed: symbol = "waveform"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pith · \(model.statusMessage)")
        statusItem?.button?.toolTip = "Pith · \(model.shortcutHint)"
        guard model.presentation != .hidden else {
            voicePanel?.orderOut(nil)
            return
        }
        showVoicePanel()
        if model.presentation == .resultCard {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.model.presentation == .resultCard else { return }
                    self.model.dismissPresentation()
                }
            }
        }
    }

    private func showVoicePanel() {
        if voicePanel == nil {
            let panel = VoicePanel(contentRect: .zero,
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: SessionOverlayView(
                model: model,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onDismiss: { [weak self] in self?.model.dismissPresentation() },
                onOpenEditor: { [weak self] in self?.openEditor() }
            ))
            voicePanel = panel
        }
        let isResult = model.presentation == .resultCard
        let size = isResult
            ? NSSize(width: ResultCardView.width, height: ResultCardView.height(for: model.result?.text ?? ""))
            : VoiceBarView.size(for: model.phase)
        voicePanel?.allowsKeyFocus = isResult
        voicePanel?.title = isResult ? "Pith 结果卡片" : "Pith 录音条"
        voicePanel?.setContentSize(size)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            voicePanel?.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 32))
        }
        // Neither recording nor completion activates Pith or opens its editor.
        voicePanel?.orderFrontRegardless()
    }

    private func showShortcutHint(_ visible: Bool) {
        guard visible else {
            shortcutHintPanel?.orderOut(nil)
            shortcutHintPanel?.close()
            shortcutHintPanel = nil
            return
        }
        guard shortcutHintPanel == nil, !model.phase.isActive else { return }
        let panel = VoicePanel(contentRect: NSRect(origin: .zero, size: ShortcutHintView.size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Pith 快捷键"
        panel.contentView = NSHostingView(rootView: ShortcutHintView())
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - ShortcutHintView.size.width / 2, y: frame.minY + 120))
        }
        shortcutHintPanel = panel
        panel.orderFrontRegardless()
    }

    private func openSettings() {
        model.refreshReadiness()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Pith 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 540, height: 700))
            window.minSize = NSSize(width: 520, height: 520)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func openLibrary() {
        if libraryWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: LibraryView(model: model)))
            window.title = "Pith · 词典与历史"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 640, height: 620))
            window.minSize = NSSize(width: 580, height: 480)
            window.center()
            window.isReleasedWhenClosed = false
            libraryWindow = window
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    private func openEditor() {
        if editorWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ResultEditorView(model: model)))
            window.title = "Pith · 编辑文字"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 740, height: 760))
            window.minSize = NSSize(width: 690, height: 680)
            window.center()
            window.isReleasedWhenClosed = false
            editorWindow = window
        }
        popover.performClose(nil)
        model.dismissPresentation()
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }
}

final class VoicePanel: NSPanel {
    var allowsKeyFocus = false
    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}
