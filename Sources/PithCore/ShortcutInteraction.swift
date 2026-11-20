import Foundation

public enum DictationShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case function
    case controlOptionSpace
    case controlShiftSpace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .function: "Fn / 🌐"
        case .controlOptionSpace: "⌃ ⌥ Space"
        case .controlShiftSpace: "⌃ ⇧ Space"
        }
    }
}

public enum ShortcutActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggle
    case hold

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toggle: "按一下开始，再按一下结束"
        case .hold: "按住说话，松开结束"
        }
    }
}

public enum ShortcutAction: Equatable, Sendable {
    case none
    case start
    case stop
    case cancel
}

/// Turns a matched shortcut's press/release pair into session actions.
/// Ordinary keyboard events must never be forwarded to this state machine.
public struct ShortcutInteraction: Sendable {
    public var mode: ShortcutActivationMode {
        didSet { reset() }
    }
    private var pressedKeys: Set<String> = []
    private var owner: String?
    private var ownerMode: ShortcutActivationMode?
    public var isPressed: Bool { !pressedKeys.isEmpty }
    public var ownsSession: Bool { owner != nil }
    public var isHolding: Bool { owner != nil && ownerMode == .hold }

    public init(mode: ShortcutActivationMode = .toggle) {
        self.mode = mode
    }

    /// Ignores repeats and never starts a second session while work is in progress.
    public mutating func keyPressed(phase: SessionPhase, trigger: String = "primary",
                                   activation: ShortcutActivationMode? = nil) -> ShortcutAction {
        guard pressedKeys.insert(trigger).inserted else { return .none }
        let activation = activation ?? mode

        switch phase {
        case .idle, .completed, .failed:
            owner = trigger
            ownerMode = activation
            return .start
        case .recording where activation == .toggle:
            owner = nil
            ownerMode = nil
            return .stop
        case .requestingPermission where activation == .toggle && ownsSession:
            owner = nil
            ownerMode = nil
            return .cancel
        default:
            return .none
        }
    }

    /// A release only controls a hold session that this shortcut actually started.
    public mutating func keyReleased(phase: SessionPhase, trigger: String = "primary") -> ShortcutAction {
        guard pressedKeys.remove(trigger) != nil else { return .none }
        guard ownerMode == .hold, owner == trigger else { return .none }
        owner = nil
        ownerMode = nil

        switch phase {
        case .recording: return .stop
        case .requestingPermission: return .cancel
        default: return .none
        }
    }

    /// Clears ownership after cancellation, failure, or a shortcut preference change.
    public mutating func reset() {
        pressedKeys.removeAll()
        owner = nil
        ownerMode = nil
    }
}
