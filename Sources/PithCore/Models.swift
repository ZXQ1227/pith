import Foundation

public enum DictationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case dictate
    case rewrite
    case translate
    case ask

    public static let textModes: [Self] = [.dictate, .rewrite, .translate]
    public static let voiceModes: [Self] = [.dictate, .translate, .ask]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dictate: "口述"
        case .rewrite: "润色"
        case .translate: "翻译"
        case .ask: "问任何问题"
        }
    }

    public var systemInstruction: String {
        switch self {
        case .dictate:
            "整理口述原文：准确保留原意，只删除明显的口头填充词并修正标点。只输出整理后的文本。"
        case .rewrite:
            "润色口述原文：使现有内容清晰、自然、简洁，不添加事实，不扩写成新的内容。只输出润色后的文本。"
        case .translate:
            "将用户口述内容翻译成简体中文，保留语气和专有名词。只输出译文，不要解释。"
        case .ask:
            "根据用户的口述要求编辑选中文字或回答问题。"
        }
    }
}

public enum SessionPhase: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording
    case processing
    case inserting
    case completed
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .requestingPermission, .recording, .processing, .inserting: true
        case .idle, .completed, .failed: false
        }
    }

    public var canStart: Bool { !isActive }
}

public enum TranscriptionSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case api, system
    public var id: String { rawValue }
    public var title: String { self == .system ? "macOS 系统语音识别" : "API 语音转写" }
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public var baseURL: String
    public var transcriptionModel: String
    public var textModel: String
    public var transcriptionSource: TranscriptionSource
    public var speechLocale: String

    public init(
        baseURL: String = "https://api.openai.com/v1",
        transcriptionModel: String = "gpt-4o-mini-transcribe",
        textModel: String = "gpt-4.1-mini",
        transcriptionSource: TranscriptionSource = .api,
        speechLocale: String = "zh-CN"
    ) {
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.textModel = textModel
        self.transcriptionSource = transcriptionSource
        self.speechLocale = speechLocale
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        transcriptionModel = try values.decode(String.self, forKey: .transcriptionModel)
        textModel = try values.decode(String.self, forKey: .textModel)
        transcriptionSource = try values.decodeIfPresent(TranscriptionSource.self, forKey: .transcriptionSource) ?? .api
        speechLocale = try values.decodeIfPresent(String.self, forKey: .speechLocale) ?? "zh-CN"
    }

    public func validatedBaseURL() throws -> URL {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil,
              url.query == nil,
              url.fragment == nil else {
            throw PithError.invalidConfiguration("API 地址必须是有效的 HTTP 或 HTTPS URL。")
        }
        return url
    }
}

public struct ProviderResult: Equatable, Sendable {
    public let transcription: String
    public let text: String
    public let refinementWarning: String?

    public init(transcription: String, text: String, refinementWarning: String? = nil) {
        self.transcription = transcription
        self.text = text
        self.refinementWarning = refinementWarning
    }
}

public struct PithContext: Equatable, Sendable {
    public let appName: String?
    public let bundleIdentifier: String?

    public init(appName: String? = nil, bundleIdentifier: String? = nil) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum PithError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case missingAPIKey
    case invalidResponse
    case provider(String)
    case recording(String)
    case permissionDenied(String)
    case insertion(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message), let .provider(message),
             let .recording(message), let .permissionDenied(message), let .insertion(message):
            message
        case .missingAPIKey:
            "请先在设置中填写 API Key。"
        case .invalidResponse:
            "API 返回了无法识别的响应。"
        }
    }
}

public enum ContextPolicy {
    public static let defaultBlockedBundlePrefixes = [
        "com.1password.", "com.agilebits.onepassword", "com.apple.keychainaccess",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.bank.",
    ]

    public static func shouldBlock(bundleIdentifier: String?, additionalPrefixes: [String] = []) -> Bool {
        guard let bundleIdentifier else { return true }
        let normalized = bundleIdentifier.lowercased()
        return (defaultBlockedBundlePrefixes + additionalPrefixes)
            .contains { normalized.hasPrefix($0.lowercased()) }
    }

    public static func limited(_ value: String?, maximumCharacters: Int = 500) -> String? {
        guard let value, maximumCharacters > 0 else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumCharacters))
    }
}
