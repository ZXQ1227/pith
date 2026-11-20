import Foundation

public enum ShortcutIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictate, translate, ask
    public var id: String { rawValue }
    public var title: String { mode.title }
    public var mode: DictationMode {
        switch self {
        case .dictate: .dictate
        case .translate: .translate
        case .ask: .ask
        }
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)

    public var title: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined(separator: " ")
    }
}

/// A key combination has one intent. Physical identity, rather than the label, detects conflicts.
public struct ShortcutBinding: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    public let keyLabel: String
    public let intent: ShortcutIntent

    public init(id: UUID = UUID(), keyCode: UInt16, modifiers: ShortcutModifiers,
                keyLabel: String, intent: ShortcutIntent) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
        self.intent = intent
    }

    public var title: String { "\(modifiers.title) \(keyLabel)" }

    public func matches(_ other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Keeps ordinary typing, modifier-only keys and standard Command shortcuts out of Carbon.
    public func validate() throws {
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        let known: ShortcutModifiers = [.control, .option, .shift, .command]
        guard keyCode < 128, !modifierKeys.contains(keyCode), keyCode != 53,
              !modifiers.intersection([.control, .option, .command]).isEmpty,
              modifiers.subtracting(known).isEmpty,
              modifiers != [.command], !keyLabel.isEmpty, keyLabel.count <= 24 else {
            throw PithError.invalidConfiguration("请使用 Control、Option 或多个修饰键搭配一个普通按键；Esc 和单独的 Command 快捷键留给系统。")
        }
    }

    public static func preset(_ shortcut: DictationShortcut) -> Self? {
        switch shortcut {
        case .function: nil
        case .controlOptionSpace: .init(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space", intent: .dictate)
        case .controlShiftSpace: .init(keyCode: 49, modifiers: [.control, .shift], keyLabel: "Space", intent: .dictate)
        }
    }

    public static var translationFallback: Self {
        .init(keyCode: 49, modifiers: [.control, .option, .shift], keyLabel: "Space", intent: .translate)
    }
}

/// Recognizes the three reserved Fn gestures on release while rejecting unrelated chords.
public struct FunctionKeyGesture: Sendable {
    public private(set) var isDown = false
    public private(set) var isHintVisible = false
    private var blocked = false
    private var intent = ShortcutIntent.dictate

    public init() {}

    public var canRevealHint: Bool { isDown && !blocked && intent == .dictate && !isHintVisible }

    /// A long bare Fn stroke is help, so releasing it must not start a recording.
    @discardableResult
    public mutating func revealHint() -> Bool {
        guard canRevealHint else { return false }
        isHintVisible = true
        return true
    }

    /// Only a physical Fn event begins/ends a stroke; Shift may join in either press order.
    public mutating func flagsChanged(isFunctionEvent: Bool, functionDown: Bool,
                                      leftShiftDown: Bool, otherModifiersDown: Bool,
                                      ordinaryKeyAlreadyDown: Bool = false) -> ShortcutIntent? {
        if isFunctionEvent, functionDown, !isDown {
            isDown = true
            blocked = otherModifiersDown || ordinaryKeyAlreadyDown
            intent = leftShiftDown ? .translate : .dictate
            return nil
        }
        guard isDown else { return nil }
        if otherModifiersDown { blocked = true; isHintVisible = false }
        if leftShiftDown {
            isHintVisible = false
            if intent == .ask { blocked = true }
            else { intent = .translate }
        }
        if isFunctionEvent, !functionDown {
            let result = blocked || isHintVisible ? nil : intent
            reset()
            return result
        }
        return nil
    }

    /// We only observe that a chord occurred, never store the typed character or key.
    public mutating func ordinaryKeyPressed() {
        if isDown { blocked = true; isHintVisible = false }
    }

    /// Reserves Space only within a valid Fn stroke; repeats cannot create additional actions.
    @discardableResult
    public mutating func spacePressed() -> Bool {
        guard isDown, !blocked else { return false }
        guard intent != .translate else { blocked = true; return false }
        isHintVisible = false
        intent = .ask
        return true
    }

    /// Prevents a release after sleep, permission loss or an event-tap interruption from firing.
    public mutating func reset() {
        isDown = false
        isHintVisible = false
        blocked = false
        intent = .dictate
    }
}
