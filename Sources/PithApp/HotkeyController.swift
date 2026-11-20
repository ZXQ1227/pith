import AppKit
import Carbon
import PithCore

/// Carbon handles ordinary combinations; a permission-gated event tap handles Fn modifier gestures.
@MainActor
final class HotkeyController {
    private static let signature: OSType = 0x50697468 // Pith
    private static let cancelID: UInt32 = 1
    private static let firstBindingID: UInt32 = 10
    private let onPress: @MainActor (String, ShortcutIntent, Bool) -> Void
    private let onRelease: @MainActor (String) -> Void
    private let onCancel: @MainActor () -> Void
    private let onReset: @MainActor () -> Void
    private let onStatusChange: @MainActor (String?) -> Void
    private var primary: DictationShortcut = .function
    private var additional: [ShortcutBinding] = []
    private var eventHandler: EventHandlerRef?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var bindings: [UInt32: ShortcutBinding] = [:]
    private var pressed: Set<UInt32> = []
    private var cancelHotkey: EventHotKeyRef?
    private var cancelPressed = false
    private var sessionActive = false
    private var suspended = false
    private var invalidated = false
    private var observers: [NSObjectProtocol] = []
    private var registrationErrors: [String] = []
    private var functionError: String?
    private var cancellationError: String?
    private let onHintChange: @MainActor (Bool) -> Void
    private let canShowHint: @MainActor () -> Bool
    private lazy var functionMonitor = FunctionKeyMonitor(onTrigger: { [weak self] intent in
        guard let self, !self.suspended, !self.invalidated else { return }
        let trigger = "function"
        self.onPress(trigger, intent, true)
        self.onRelease(trigger)
    }, onHintChange: onHintChange, canShowHint: canShowHint)

    init(onPress: @escaping @MainActor (String, ShortcutIntent, Bool) -> Void,
         onRelease: @escaping @MainActor (String) -> Void,
         onCancel: @escaping @MainActor () -> Void,
         onReset: @escaping @MainActor () -> Void,
         onStatusChange: @escaping @MainActor (String?) -> Void,
         onHintChange: @escaping @MainActor (Bool) -> Void = { _ in },
         canShowHint: @escaping @MainActor () -> Bool = { true }) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
        self.onReset = onReset
        self.onStatusChange = onStatusChange
        self.onHintChange = onHintChange
        self.canShowHint = canShowHint
        observeWorkspace()
    }
    isolated deinit { invalidate() }

    func configure(_ primary: DictationShortcut, additional: [ShortcutBinding]) {
        guard !invalidated else { return }
        self.primary = primary
        self.additional = additional
        registerBindings()
    }

    /// Temporarily releases global combinations while the settings recorder captures a new one.
    func setSuspended(_ value: Bool) {
        guard !invalidated, suspended != value else { return }
        suspended = value
        if value { unregisterBindings(); functionMonitor.stop() }
        else { registerBindings() }
    }

    func refreshFunctionKeyAccess() {
        guard !invalidated, !suspended, primary == .function else { return }
        functionError = functionMonitor.refresh()
        publishStatus()
    }

    /// Escape is exclusive only for an active operation, not normal typing.
    func setSessionActive(_ active: Bool) {
        sessionActive = active
        if active { registerCancel() }
        else {
            if let cancelHotkey { UnregisterEventHotKey(cancelHotkey) }
            cancelHotkey = nil
            cancelPressed = false
            cancellationError = nil
            publishStatus()
        }
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        unregisterBindings()
        functionMonitor.stop()
        if let cancelHotkey { UnregisterEventHotKey(cancelHotkey) }
        cancelHotkey = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func installHandler() -> OSStatus {
        guard eventHandler == nil else { return noErr }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard status == noErr else { return status }
            let controller = Unmanaged<HotkeyController>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { controller.handle(hotkey, kind: GetEventKind(event)) }
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func registerBindings() {
        guard !suspended, !invalidated else { return }
        unregisterBindings()
        registrationErrors = []
        var requested = additional
        if let preset = ShortcutBinding.preset(primary) {
            if requested.contains(where: { $0.matches(preset) && $0.intent != .dictate }) {
                registrationErrors.append("\(preset.title) 与主听写快捷键重复，已停用该翻译绑定，请修改。")
            }
            requested.removeAll { $0.matches(preset) }
            requested.insert(preset, at: 0)
        }
        let handlerStatus = installHandler()
        if handlerStatus == noErr {
            for (index, binding) in requested.enumerated() {
                do { try binding.validate() }
                catch { registrationErrors.append("\(binding.title)：\(error.localizedDescription)"); continue }
                let id = Self.firstBindingID + UInt32(index)
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(UInt32(binding.keyCode), binding.modifiers.carbonFlags,
                    EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
                if status == noErr, let reference {
                    references[id] = reference
                    bindings[id] = binding
                } else {
                    // Observing an occupied shortcut would trigger both apps, so never silently fall back.
                    registrationErrors.append(status == eventHotKeyExistsErr
                        ? "\(binding.title) 已被占用，请修改这个快捷键。"
                        : "\(binding.title) 注册失败（\(status)），请换一个组合键。")
                }
            }
        } else { registrationErrors.append("系统快捷键启动失败（\(handlerStatus)），请重新启动 Pith。") }
        if primary == .function { functionError = functionMonitor.refresh() }
        else { functionMonitor.stop(); functionError = nil }
        if sessionActive { registerCancel() }
        publishStatus()
    }

    private func registerCancel() {
        guard !invalidated, !suspended, cancelHotkey == nil else { return }
        guard installHandler() == noErr else {
            cancellationError = "Esc 不可用，请点击录音条的取消按钮。"
            publishStatus()
            return
        }
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0,
            EventHotKeyID(signature: Self.signature, id: Self.cancelID), GetApplicationEventTarget(), 0, &cancelHotkey)
        cancellationError = status == noErr ? nil : "Esc 已被占用，请点击录音条的取消按钮。"
        publishStatus()
    }

    private func handle(_ hotkey: EventHotKeyID, kind: UInt32) -> OSStatus {
        guard !invalidated, !suspended, hotkey.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        if hotkey.id == Self.cancelID {
            if kind == kEventHotKeyPressed, sessionActive, !cancelPressed { cancelPressed = true; onCancel() }
            else if kind == kEventHotKeyReleased { cancelPressed = false }
        } else if let binding = bindings[hotkey.id] {
            let trigger = binding.id.uuidString
            if kind == kEventHotKeyPressed, pressed.insert(hotkey.id).inserted { onPress(trigger, binding.intent, false) }
            else if kind == kEventHotKeyReleased, pressed.remove(hotkey.id) != nil { onRelease(trigger) }
        }
        return noErr
    }

    private func unregisterBindings() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll()
        bindings.removeAll()
        pressed.removeAll()
        onReset()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pressed.removeAll()
                    self.functionMonitor.resetGesture()
                    if self.sessionActive { self.onCancel() }
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.registerBindings() }
            })
        }
    }

    private func publishStatus() {
        let messages = registrationErrors + [functionError, cancellationError].compactMap { $0 }
        onStatusChange(messages.isEmpty ? nil : messages.joined(separator: "\n"))
    }
}

extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        self.init(rawValue: 0)
        if eventFlags.contains(.control) { insert(.control) }
        if eventFlags.contains(.option) { insert(.option) }
        if eventFlags.contains(.shift) { insert(.shift) }
        if eventFlags.contains(.command) { insert(.command) }
    }
}
