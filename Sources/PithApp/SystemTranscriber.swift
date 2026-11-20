import Foundation
import PithCore
import Speech

/// Owns one recognition request and resolves it exactly once on success, failure, timeout, or cancellation.
@MainActor
final class SystemTranscriber {
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeoutTask: Task<Void, Never>?

    /// Speech authorization may complete on any queue; no UI state belongs in this bridge.
    nonisolated static func authorize(
        currentStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus(),
        requestAuthorization: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
            = { SFSpeechRecognizer.requestAuthorization($0) }
    ) async throws {
        let status: SFSpeechRecognizerAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await withCheckedContinuation { continuation in
                requestAuthorization { @Sendable status in continuation.resume(returning: status) }
            }
        } else {
            status = currentStatus
        }
        try Task.checkCancellation()
        guard status == .authorized else {
            throw PithError.permissionDenied("请在系统设置 → 隐私与安全性 → 语音识别中允许 Pith。")
        }
    }

    func transcribe(audioURL: URL, locale: String, words: [String]) async throws -> String {
        try await Self.authorize()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw PithError.recording("系统语音识别暂不可用，请检查网络及所选识别语言后重试。")
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.contextualStrings = words
        // Prefer local recognition when supported. Otherwise Apple's permission prompt governs server processing.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    let message = error?.localizedDescription
                    Task { @MainActor [weak self] in
                        if let text {
                            self?.finish(text.isEmpty
                                ? .failure(PithError.recording("未识别到文字，请说话后重试。")) : .success(text))
                        } else if let message {
                            self?.finish(.failure(PithError.recording("系统语音识别失败：\(message)")))
                        }
                    }
                }
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) }
                    catch { return }
                    self?.finish(.failure(PithError.recording("系统语音识别超时，请检查网络后重试。")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ outcome: Result<String, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        continuation.resume(with: outcome)
    }
}
