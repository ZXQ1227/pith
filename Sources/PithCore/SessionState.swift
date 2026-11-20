import Foundation

/// Identifies each recording so cancelled or superseded asynchronous work cannot update it.
public struct SessionState: Sendable {
    public private(set) var phase: SessionPhase = .idle
    public private(set) var sessionID: UUID?

    public init() {}

    public mutating func begin() -> UUID? {
        begin(in: .requestingPermission)
    }

    /// Starts a retry or text-only operation without pretending to record audio.
    public mutating func beginProcessing() -> UUID? {
        begin(in: .processing)
    }

    private mutating func begin(in phase: SessionPhase) -> UUID? {
        guard self.phase.canStart else { return nil }
        let id = UUID()
        sessionID = id
        self.phase = phase
        return id
    }

    public func isCurrent(_ id: UUID) -> Bool { sessionID == id }

    @discardableResult
    public mutating func transition(to next: SessionPhase, for id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        switch (phase, next) {
        case (.requestingPermission, .recording), (.recording, .processing),
             (.processing, .inserting), (.processing, .completed), (.inserting, .completed):
            break
        case (_, .failed) where phase.isActive:
            break
        default:
            return false
        }
        phase = next
        if !next.isActive { sessionID = nil }
        return true
    }

    public mutating func cancel() {
        sessionID = nil
        phase = .idle
    }
}
