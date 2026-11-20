import Foundation

public enum CompletionDisposition: Equatable, Sendable {
    case copyNeeded, inserted, answer
}

public enum SessionPresentation: Equatable, Sendable {
    case hidden, voiceBar, resultCard

    /// Successful paste ends the overlay immediately; questions never paste into the current field.
    public static func resolve(phase: SessionPhase, completion: CompletionDisposition,
                               hasInputTarget: Bool) -> Self {
        switch phase {
        case .idle: .hidden
        case .requestingPermission, .recording, .processing, .inserting, .failed: .voiceBar
        case .completed:
            switch completion {
            case .inserted: .hidden
            case .answer: .resultCard
            case .copyNeeded: hasInputTarget ? .voiceBar : .resultCard
            }
        }
    }
}
