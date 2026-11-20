import Foundation
import Testing
@testable import PithCore

@Suite("Pith core")
struct PithCoreTests {
    @Test("rejects non-HTTP provider URLs")
    func rejectsInvalidURL() {
        let configuration = ProviderConfiguration(baseURL: "file:///tmp/api")
        #expect(throws: PithError.self) { try configuration.validatedBaseURL() }
        let queryURL = ProviderConfiguration(baseURL: "https://api.example.test/v1?debug=1")
        #expect(throws: PithError.self) { try queryURL.validatedBaseURL() }
    }

    @Test("accepts a valid custom provider URL")
    func acceptsCustomURL() throws {
        let configuration = ProviderConfiguration(baseURL: "https://api.example.test/v1")
        #expect(try configuration.validatedBaseURL().host == "api.example.test")
    }

    @Test("checks API key before attempting to read audio")
    func requiresAPIKey() async {
        let client = ProviderClient(configuration: ProviderConfiguration(), apiKey: "")
        await #expect(throws: PithError.missingAPIKey) {
            try await client.process(audioURL: URL(fileURLWithPath: "/not-read.m4a"), mode: .dictate)
        }
    }

    @Test("blocks sensitive app identifiers and unknown identities")
    func blocksSensitiveApps() {
        #expect(ContextPolicy.shouldBlock(bundleIdentifier: "com.apple.Terminal"))
        #expect(ContextPolicy.shouldBlock(bundleIdentifier: "com.1password.1password"))
        #expect(ContextPolicy.shouldBlock(bundleIdentifier: nil))
        #expect(!ContextPolicy.shouldBlock(bundleIdentifier: "md.obsidian"))
    }

    @Test("limits context without splitting user-visible text")
    func limitsContext() {
        #expect(ContextPolicy.limited("  hello  ") == "hello")
        #expect(ContextPolicy.limited(String(repeating: "界", count: 4), maximumCharacters: 2) == "界界")
        #expect(ContextPolicy.limited(" \n ") == nil)
    }

    @Test("provides distinct mode instructions")
    func modesHaveInstructions() {
        #expect(DictationMode.allCases.count == 4)
        #expect(DictationMode.voiceModes == [.dictate, .translate, .ask])
        #expect(DictationMode.textModes == [.dictate, .rewrite, .translate])
        #expect(DictationMode.dictate.systemInstruction != DictationMode.translate.systemInstruction)
    }
}
