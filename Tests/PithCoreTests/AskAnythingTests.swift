import Foundation
import Testing
@testable import PithCore

@Suite("Ask intent and result delivery")
struct AskAnythingTests {
    @Test("unavailable insertion capabilities always degrade to a readable answer")
    func capabilityBoundary() throws {
        let replacement = #"{"action":"replaceSelection","text":" 新文字 "}"#
        #expect(try AskResult.decode(replacement, context: .init()).action == .answer)
        #expect(try AskResult.decode(replacement, context: .init(selectedText: "原文")).action == .answer)
        let editable = AskContext(selectedText: "原文", canInsert: true, canReplaceSelection: true)
        #expect(!editable.canInsert)
        let result = try AskResult.decode(replacement, context: editable)
        #expect(result == AskResult(action: .replaceSelection, text: "新文字"))
        let draft = #"{"action":"insert","text":"邮件正文"}"#
        #expect(try AskResult.decode(draft, context: editable).action == .answer)
        #expect(try AskResult.decode(draft, context: .init(canInsert: true)).action == .insert)
        #expect(try AskResult.decode(#"{"action":"answer","text":"解释"}"#, context: editable).action == .answer)
    }

    @Test("unknown actions, empty text and malformed output never become a paste")
    func malformedOutput() {
        for content in ["正文", #"{"action":"execute","text":"命令"}"#, #"{"action":"insert","text":"  "}"#] {
            #expect(throws: PithError.self) { try AskResult.decode(content, context: .init(canInsert: true)) }
        }
    }

    @Test("JSON code fences and selected-text limits are handled without truncating the source")
    func boundedContext() throws {
        let result = try AskResult.decode("```json\n{\"action\":\"answer\",\"text\":\"解释\"}\n```", context: .init())
        #expect(result.text == "解释")
        try AskContext(selectedText: String(repeating: "字", count: AskContext.maximumSelectionLength)).validate()
        #expect(throws: PithError.self) {
            try AskContext(selectedText: String(repeating: "字", count: AskContext.maximumSelectionLength + 1)).validate()
        }
        #expect(!AskContext(canReplaceSelection: true).canReplaceSelection)
    }

    @Test("successful input has no completion window; answers always remain separate")
    func completedPresentation() {
        for hasTarget in [true, false] {
            #expect(SessionPresentation.resolve(phase: .completed, completion: .inserted, hasInputTarget: hasTarget) == .hidden)
            #expect(SessionPresentation.resolve(phase: .completed, completion: .answer, hasInputTarget: hasTarget) == .resultCard)
        }
        #expect(SessionPresentation.resolve(phase: .completed, completion: .copyNeeded, hasInputTarget: true) == .voiceBar)
        #expect(SessionPresentation.resolve(phase: .completed, completion: .copyNeeded, hasInputTarget: false) == .resultCard)
    }

    @Test("recording, processing and failures never open a result window")
    func transientPresentation() {
        for phase in [SessionPhase.requestingPermission, .recording, .processing, .inserting, .failed("offline")] {
            #expect(SessionPresentation.resolve(phase: phase, completion: .answer, hasInputTarget: true) == .voiceBar)
        }
        #expect(SessionPresentation.resolve(phase: .idle, completion: .answer, hasInputTarget: true) == .hidden)
    }
}
