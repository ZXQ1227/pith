import Foundation
import PithCore
import Speech
import Testing
@testable import PithApp

@Suite("Speech authorization callback isolation")
@MainActor
struct SpeechAuthorizationTests {
    @Test("a background authorization callback safely resumes the main-actor caller")
    func backgroundAuthorization() async throws {
        try await SystemTranscriber.authorize(currentStatus: .notDetermined) { completion in
            DispatchQueue.global().async {
                #expect(!Thread.isMainThread)
                completion(.authorized)
            }
        }
        MainActor.assertIsolated()
    }

    @Test("denying a background prompt returns an actionable error instead of crashing")
    func backgroundDenial() async {
        await #expect(throws: PithError.permissionDenied("请在系统设置 → 隐私与安全性 → 语音识别中允许 Pith。")) {
            try await SystemTranscriber.authorize(currentStatus: .notDetermined) { completion in
                DispatchQueue.global().async { completion(.denied) }
            }
        }
    }

    @Test("existing authorization does not prompt again")
    func alreadyAuthorized() async throws {
        try await SystemTranscriber.authorize(currentStatus: .authorized) { _ in
            Issue.record("Already authorized speech must not show another prompt")
        }
    }

    @Test("denied and restricted permissions do not request another prompt", arguments: [
        SFSpeechRecognizerAuthorizationStatus.denied, .restricted,
    ])
    func existingDenial(status: SFSpeechRecognizerAuthorizationStatus) async {
        await #expect(throws: PithError.permissionDenied("请在系统设置 → 隐私与安全性 → 语音识别中允许 Pith。")) {
            try await SystemTranscriber.authorize(currentStatus: status) { _ in
                Issue.record("Known denied or restricted speech permission must not prompt again")
            }
        }
    }

    @Test("cancellation while the prompt is open rejects late authorization")
    func cancellationWhilePending() async throws {
        typealias Completion = @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
        let (callbacks, stream) = AsyncStream<Completion>.makeStream()
        let task = Task {
            try await SystemTranscriber.authorize(currentStatus: .notDetermined) { completion in
                stream.yield(completion)
                stream.finish()
            }
        }
        var iterator = callbacks.makeAsyncIterator()
        let completion = try #require(await iterator.next())
        task.cancel()
        await Task.detached { completion(.authorized) }.value
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
