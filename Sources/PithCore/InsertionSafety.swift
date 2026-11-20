import Foundation

/// Accessibility-reported caret metadata, independent of Ask's explicitly selected source text.
public struct TextSelectionRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public enum InsertionSafety {
    /// The caller verifies field identity. Missing caret metadata is allowed only for ordinary input.
    public static func selectionMatches(
        original: TextSelectionRange?,
        current: TextSelectionRange?,
        automatic: Bool,
        requiresKnownRange: Bool = false
    ) -> Bool {
        guard automatic else { return true }
        if original == nil, current == nil { return !requiresKnownRange }
        guard let original, let current else { return false }
        return original == current
    }
}
