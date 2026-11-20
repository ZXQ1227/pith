import Foundation

public enum DraftSource: String, CaseIterable, Identifiable, Sendable {
    case current, original
    public var id: String { rawValue }
    public var title: String { self == .current ? "当前文字" : "原始转写" }
}

public struct DraftSettings: Equatable, Sendable {
    public var mode: DictationMode
    public var style: OutputStyle
    public var language: OutputLanguage

    public init(mode: DictationMode = .dictate, style: OutputStyle = .natural,
                language: OutputLanguage = .simplifiedChinese) {
        self.mode = mode
        self.style = style
        self.language = language
    }
}

/// Keeps the recognized original separate from edits and generated versions, in memory only.
public struct TextDraft: Equatable, Sendable {
    public let transcription: String
    public private(set) var text: String
    public private(set) var isRefined: Bool
    public private(set) var settings: DraftSettings
    private var previous: Version?

    private struct Version: Equatable, Sendable {
        let text: String
        let isRefined: Bool
        let settings: DraftSettings
    }

    public init(transcription: String, settings: DraftSettings = .init()) {
        self.transcription = transcription
        text = transcription
        isRefined = false
        self.settings = settings
    }

    public var canRestorePrevious: Bool { previous != nil }

    public var result: ProviderResult {
        ProviderResult(transcription: transcription, text: text,
                       refinementWarning: isRefined ? nil : "原始转写 · 尚未整理或翻译")
    }

    /// Chooses an explicit source so changing language need not translate a previous translation.
    public func sourceText(_ source: DraftSource) -> String {
        source == .original ? transcription : text
    }

    /// Commits an editor change as one recoverable version, preserving the original recognition.
    @discardableResult
    public mutating func edit(_ newText: String) -> Bool {
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        replace(with: newText, isRefined: true, settings: settings)
        return true
    }

    /// Failed refinement must not replace a good version or the user's manual corrections.
    @discardableResult
    public mutating func apply(_ output: ProviderResult, settings: DraftSettings = .init()) -> Bool {
        guard output.refinementWarning == nil,
              !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        replace(with: output.text, isRefined: true, settings: settings)
        return true
    }

    /// Restores the last committed version once; the original is always independently available.
    public mutating func restorePrevious() {
        guard let previous else { return }
        text = previous.text
        isRefined = previous.isRefined
        settings = previous.settings
        self.previous = nil
    }

    private mutating func replace(with newText: String, isRefined: Bool, settings: DraftSettings) {
        guard newText != text || self.isRefined != isRefined || self.settings != settings else { return }
        previous = Version(text: text, isRefined: self.isRefined, settings: self.settings)
        text = newText
        self.isRefined = isRefined
        self.settings = settings
    }
}

/// Once recognition succeeds, retries use a text checkpoint rather than resubmitting audio.
public enum ProcessingInput: Equatable, Sendable {
    case audio(URL)
    case text(String)

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    /// Invokes speech recognition only for audio; rejects empty results before refinement.
    public func transcription(isolation: isolated (any Actor)? = #isolation,
                              using recognize: (URL) async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let text: String
        switch self {
        case let .audio(url): text = try await recognize(url)
        case let .text(cached): text = cached
        }
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PithError.recording("未识别到文字，请确认录音语言后重试。")
        }
        return text
    }
}
