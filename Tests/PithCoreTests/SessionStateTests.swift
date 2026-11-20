import Testing
@testable import PithCore

@Suite("Session cancellation and ordering")
struct SessionStateTests {
    @Test("text processing starts directly and rejects late completion after cancellation")
    func textProcessing() throws {
        var state = SessionState()
        let started = state.beginProcessing()
        let first = try #require(started)
        #expect(state.phase == .processing)
        #expect(state.beginProcessing() == nil)
        #expect(state.begin() == nil)
        state.cancel()
        let retry = state.beginProcessing()
        let second = try #require(retry)
        #expect(first != second)
        #expect((!state.transition(to: .completed, for: first)) == true)
        #expect((state.transition(to: .failed("offline"), for: second)) == true)
        #expect(state.beginProcessing() != nil)
    }

    @Test("cancelling while permission is pending prevents late recording")
    func pendingPermissionCancellation() throws {
        var state = SessionState()
        let oldValue = state.begin()
        let old = try #require(oldValue)
        state.cancel()
        #expect((state.transition(to: .recording, for: old)) == false)
        #expect(state.phase == .idle)
    }

    @Test("old network response cannot overwrite a new recording")
    func staleNetworkResponse() throws {
        var state = SessionState()
        let oldValue = state.begin()
        let old = try #require(oldValue)
        #expect((state.transition(to: .recording, for: old)) == true)
        #expect((state.transition(to: .processing, for: old)) == true)
        state.cancel()
        let currentValue = state.begin()
        let current = try #require(currentValue)
        #expect((state.transition(to: .recording, for: current)) == true)
        #expect((state.transition(to: .completed, for: old)) == false)
        #expect((state.transition(to: .failed("late error"), for: old)) == false)
        #expect(state.phase == .recording)
    }

    @Test("active sessions reject duplicate starts and out-of-order completion")
    func duplicateStart() throws {
        var state = SessionState()
        let idValue = state.begin()
        let id = try #require(idValue)
        #expect(state.begin() == nil)
        #expect((state.transition(to: .completed, for: id)) == false)
        #expect((state.transition(to: .recording, for: id)) == true)
        #expect((state.transition(to: .processing, for: id)) == true)
        #expect((state.transition(to: .inserting, for: id)) == true)
        #expect(state.begin() == nil)
        #expect((state.transition(to: .completed, for: id)) == true)
        #expect((state.transition(to: .completed, for: id)) == false)
        #expect(state.begin() != nil)
    }

    @Test("permission and processing failures both allow immediate recovery")
    func errorRecovery() throws {
        var state = SessionState()
        let idValue = state.begin()
        let id = try #require(idValue)
        #expect((state.transition(to: .failed("permission denied"), for: id)) == true)
        let retryValue = state.begin()
        let retry = try #require(retryValue)
        #expect((state.transition(to: .recording, for: retry)) == true)
        #expect((state.transition(to: .processing, for: retry)) == true)
        #expect((state.transition(to: .failed("offline"), for: retry)) == true)
        #expect(state.begin() != nil)
    }
}
