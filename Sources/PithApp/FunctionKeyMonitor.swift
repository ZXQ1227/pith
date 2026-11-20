import AppKit
import ApplicationServices
import Carbon
import IOKit.hidsystem
import PithCore

/// Handles only Fn gesture metadata; typed characters are neither read nor retained.
@MainActor
final class FunctionKeyMonitor {
    private static let ordinaryKeys = (CGKeyCode(0)..<128).filter { !(54...63).contains($0) }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = FunctionKeyGesture()
    private let onTrigger: @MainActor (ShortcutIntent) -> Void
    private let ordinaryKeyIsDown: @MainActor () -> Bool
    private var generation = 0
    private var consumesSpace = false
    private var holdTask: Task<Void, Never>?
    private var hintPublished = false
    private let onHintChange: @MainActor (Bool) -> Void
    private let canShowHint: @MainActor () -> Bool
    private let holdDelay: Duration

    init(onTrigger: @escaping @MainActor (ShortcutIntent) -> Void,
         onHintChange: @escaping @MainActor (Bool) -> Void = { _ in },
         canShowHint: @escaping @MainActor () -> Bool = { true },
         holdDelay: Duration = .milliseconds(600),
         ordinaryKeyIsDown: @escaping @MainActor () -> Bool = {
             ordinaryKeys.contains { CGEventSource.keyState(.combinedSessionState, key: $0) }
         }) {
        self.onTrigger = onTrigger
        self.ordinaryKeyIsDown = ordinaryKeyIsDown
        self.onHintChange = onHintChange
        self.canShowHint = canShowHint
        self.holdDelay = holdDelay
    }
    isolated deinit { stop() }

    /// Called after user authorization or settings activation; never prompts for permissions itself.
    func refresh() -> String? {
        guard AXIsProcessTrusted() else {
            stop()
            return "Fn 尚未启用：请开启辅助功能权限；期间可使用下面的备用组合键。"
        }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { return nil }
        stop()
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FunctionKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            let consumed = MainActor.assumeIsolated { monitor.handle(type, event: event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return "无法监听 Fn：请检查辅助功能权限并重新启动 Pith，或使用备用组合键。"
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return "Fn 监听启动失败，请重新启动 Pith。"
        }
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return nil
    }

    func stop() {
        generation += 1
        gesture.reset()
        cancelHoldTimer()
        publishHint()
        consumesSpace = false
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    func resetGesture() {
        generation += 1
        gesture.reset()
        cancelHoldTimer()
        publishHint()
    }

    private func cancelHoldTimer() { holdTask?.cancel(); holdTask = nil }

    private func publishHint() {
        guard hintPublished != gesture.isHintVisible else { return }
        hintPublished = gesture.isHintVisible
        onHintChange(hintPublished)
    }

    private func beginHoldTimer() {
        cancelHoldTimer()
        guard gesture.canRevealHint, canShowHint() else { return }
        holdTask = Task { [weak self, holdDelay] in
            do { try await Task.sleep(for: holdDelay) }
            catch { return }
            guard let self, !Task.isCancelled, self.canShowHint() else { return }
            self.gesture.revealHint()
            self.publishHint()
        }
    }

    func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGesture()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventKeycode) == kVK_Space {
                if consumesSpace { return true }
                if gesture.spacePressed() {
                    consumesSpace = true
                    cancelHoldTimer()
                    publishHint()
                    return true
                }
            }
            gesture.ordinaryKeyPressed()
            cancelHoldTimer()
            publishHint()
            return false
        }
        if type == .keyUp {
            if event.getIntegerValueField(.keyboardEventKeycode) == kVK_Space, consumesSpace {
                consumesSpace = false
                return true
            }
            return false
        }
        guard type == .flagsChanged else { return false }
        let isFn = event.getIntegerValueField(.keyboardEventKeycode) == kVK_Function
        let flags = event.flags
        // Read the event's device flags, not current keyboard state which may have advanced.
        let leftShift = flags.rawValue & UInt64(NX_DEVICELSHIFTKEYMASK) != 0
        let rightShift = flags.rawValue & UInt64(NX_DEVICERSHIFTKEYMASK) != 0
        let otherModifiers = !flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty || rightShift
        // A key held before Fn must also suppress the gesture. Only inspect pressed state,
        // without reading characters or retaining which key was held.
        let ordinaryKeyAlreadyDown = isFn && flags.contains(.maskSecondaryFn)
            && ordinaryKeyIsDown()
        let wasDown = gesture.isDown
        if let intent = gesture.flagsChanged(isFunctionEvent: isFn, functionDown: flags.contains(.maskSecondaryFn),
                                             leftShiftDown: leftShift, otherModifiersDown: otherModifiers,
                                             ordinaryKeyAlreadyDown: ordinaryKeyAlreadyDown) {
            let currentGeneration = generation
            // Keychain/microphone work must not block the event-tap callback and disable it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.onTrigger(intent)
            }
        }
        if !wasDown, gesture.isDown { beginHoldTimer() }
        else if !gesture.canRevealHint { cancelHoldTimer() }
        publishHint()
        // Consume the dedicated Fn edge so a tap does not also open the system Globe picker.
        // Other keys and their flags pass through, preserving Fn+arrow/function-key behavior.
        return isFn
    }
}
