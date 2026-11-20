import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let mode: DictationMode
    public let targetLanguage: OutputLanguage?
    public let outputStyle: OutputStyle?
    public let transcription: String
    public let text: String
    public let isRefined: Bool

    public init(id: UUID = UUID(), createdAt: Date = Date(), mode: DictationMode,
                targetLanguage: OutputLanguage? = nil, outputStyle: OutputStyle? = nil, result: ProviderResult) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.targetLanguage = mode == .translate ? targetLanguage : nil
        self.outputStyle = outputStyle
        transcription = result.transcription
        text = result.text
        isRefined = result.refinementWarning == nil
    }

    /// Searches both representations so edits do not make the original speech unfindable.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || text.localizedStandardContains(query)
            || transcription.localizedStandardContains(query)
    }
}

/// Only explicit opt-in permits recording text; audio and API credentials never enter this store.
public struct PersonalLibrary: Codable, Equatable, Sendable {
    public static let maximumHistoryCount = 100
    public var historyEnabled = false
    public var dictionary = PersonalDictionary()
    public private(set) var history: [HistoryEntry] = []

    public init() {}

    /// Upserts a session result while honoring consent and limiting local retention.
    public mutating func record(_ entry: HistoryEntry) {
        guard historyEnabled else { return }
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
        history = Array(history.prefix(Self.maximumHistoryCount))
    }

    /// Removes the requested session only.
    public mutating func removeHistory(id: UUID) { history.removeAll { $0.id == id } }
    /// Clears text records without changing dictionary words or the consent setting.
    public mutating func clearHistory() { history.removeAll() }
}

/// Writes atomically so an interrupted save cannot destroy the previous local library.
public struct LocalLibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// Returns defaults only for a missing file; corruption and access failures remain visible.
    public func load() throws -> PersonalLibrary {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .init() }
        return try JSONDecoder().decode(PersonalLibrary.self, from: data)
    }

    /// Persists the library atomically with owner-only access and propagates write failures.
    public func save(_ library: PersonalLibrary) throws {
        let data = try JSONEncoder().encode(library)
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
