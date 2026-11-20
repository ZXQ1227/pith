import Foundation
import Testing
@testable import PithCore

@Suite("Personal dictionary and history")
struct PersonalLibraryTests {
    @Test("dictionary rejects blank, duplicate, multiline and oversized terms")
    func dictionaryValidation() throws {
        var dictionary = PersonalDictionary()
        try dictionary.add("  Pith  ")
        try dictionary.add("飞书")
        #expect(dictionary.words == ["Pith", "飞书"])
        for invalid in ["", " \n ", "pItH", "a\nb", String(repeating: "界", count: 81)] {
            #expect(throws: PithError.self) { try dictionary.add(invalid) }
        }
        #expect(dictionary.words.count == 2)
        dictionary.remove("Pith")
        #expect(dictionary.words == ["飞书"])
    }

    @Test("dictionary enforces capacity on additions and decoding")
    func dictionaryCapacity() throws {
        var dictionary = PersonalDictionary()
        for index in 0..<PersonalDictionary.maximumWords { try dictionary.add("Term\(index)") }
        #expect(throws: PithError.self) { try dictionary.add("Overflow") }
        let invalidData = try JSONEncoder().encode(["words": ["Pith", "pith"]])
        #expect(throws: PithError.self) { try JSONDecoder().decode(PersonalDictionary.self, from: invalidData) }
    }

    @Test("all translation targets affect translation only; dictionary reaches both prompts")
    func processingOptions() throws {
        var dictionary = PersonalDictionary()
        try dictionary.add("Pith")
        for language in OutputLanguage.allCases {
            let options = ProcessingOptions(targetLanguage: language, dictionary: dictionary)
            #expect(options.systemInstruction(for: .translate).contains("翻译成\(language.title)"))
            #expect(options.systemInstruction(for: .dictate).contains("保留原文语言"))
            #expect(!options.systemInstruction(for: .rewrite).contains("翻译成"))
            #expect(options.systemInstruction(for: .dictate).contains("Pith"))
            #expect(options.transcriptionHint == "Pith")
        }
        #expect(ProcessingOptions().transcriptionHint == nil)
    }

    @Test("history is opt-in, bounded, searchable and retry replaces its existing entry")
    func historyLifecycle() {
        var library = PersonalLibrary()
        let first = entry(text: "Polished output", transcription: "Original speech")
        library.record(first)
        #expect(library.history.isEmpty)
        library.historyEnabled = true
        library.record(first)
        library.record(first)
        #expect(library.history.count == 1)
        #expect(first.matches("original"))
        #expect(first.matches("POLISHED"))
        #expect(first.matches("   "))
        #expect(!first.matches("missing"))
        let replacement = HistoryEntry(id: first.id, mode: .dictate,
                                       result: ProviderResult(transcription: "Original", text: "Retried"))
        library.record(replacement)
        #expect(library.history.map(\.text) == ["Retried"])
        library.historyEnabled = false
        library.record(entry(text: "Must not save"))
        #expect(library.history.count == 1)
        library.historyEnabled = true
        for index in 0...PersonalLibrary.maximumHistoryCount { library.record(entry(text: "\(index)")) }
        #expect(library.history.count == PersonalLibrary.maximumHistoryCount)
        #expect(library.history.first?.text == "100")
        #expect(!library.history.contains { $0.id == first.id })
        if let id = library.history.first?.id { library.removeHistory(id: id) }
        #expect(library.history.count == PersonalLibrary.maximumHistoryCount - 1)
        library.clearHistory()
        #expect(library.history.isEmpty)
    }

    @Test("local library survives relaunch, has private permissions and preserves corrupt files")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        #expect(try store.load() == PersonalLibrary())
        var library = PersonalLibrary()
        try library.dictionary.add("飞书")
        library.historyEnabled = true
        library.record(entry(text: "本地文字"))
        try store.save(library)
        #expect(try LocalLibraryStore(fileURL: store.fileURL).load() == library)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        library.clearHistory()
        try store.save(library)
        #expect(try store.load().history.isEmpty)
        #expect(try store.load().dictionary.words == ["飞书"])
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: store.fileURL)
        #expect(throws: DecodingError.self) { try store.load() }
        #expect(try Data(contentsOf: store.fileURL) == corrupt)
    }

    @Test("failed translations are labeled as raw transcripts in history")
    func partialResult() {
        let record = HistoryEntry(mode: .translate, targetLanguage: .english,
                                  result: ProviderResult(transcription: "你好", text: "你好", refinementWarning: "失败"))
        #expect(!record.isRefined)
        #expect(record.targetLanguage == .english)
        #expect(entry(text: "听写").targetLanguage == nil)
    }

    private func entry(text: String, transcription: String = "原文") -> HistoryEntry {
        HistoryEntry(mode: .dictate, result: ProviderResult(transcription: transcription, text: text))
    }
}
