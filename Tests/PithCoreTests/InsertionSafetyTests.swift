import Testing
@testable import PithCore

@Suite("Insertion safety")
struct InsertionSafetyTests {
    @Test("known carets must match; missing metadata supports ordinary input but never selected-text replacement")
    func automaticInsertionPreservesChangedSelection() {
        let original = TextSelectionRange(location: 12, length: 4)
        #expect(InsertionSafety.selectionMatches(original: original, current: original, automatic: true))
        #expect(!InsertionSafety.selectionMatches(
            original: original,
            current: TextSelectionRange(location: 22, length: 0),
            automatic: true
        ))
        #expect(InsertionSafety.selectionMatches(original: nil, current: nil, automatic: true))
        #expect(!InsertionSafety.selectionMatches(original: nil, current: nil, automatic: true, requiresKnownRange: true))
        #expect(!InsertionSafety.selectionMatches(original: original, current: nil, automatic: true))
        #expect(!InsertionSafety.selectionMatches(original: nil, current: original, automatic: true))
        #expect(InsertionSafety.selectionMatches(original: nil, current: nil, automatic: false))
    }
}
