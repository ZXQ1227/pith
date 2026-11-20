import Foundation

public struct ProviderClient: Sendable {
    private let configuration: ProviderConfiguration
    private let apiKey: String
    private let session: URLSession

    public init(configuration: ProviderConfiguration, apiKey: String, session: URLSession = .shared) {
        self.configuration = configuration
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func process(audioURL: URL, mode: DictationMode, options: ProcessingOptions = .init()) async throws -> ProviderResult {
        guard !apiKey.isEmpty else { throw PithError.missingAPIKey }
        let transcription = try await transcribe(audioURL: audioURL, options: options)
        return try await process(transcription: transcription, mode: mode, options: options)
    }

    /// Refines system-recognized text without uploading audio to a text-only provider.
    public func process(transcription: String, mode: DictationMode, options: ProcessingOptions = .init()) async throws -> ProviderResult {
        guard !apiKey.isEmpty else { throw PithError.missingAPIKey }
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PithError.recording("未识别到文字，请确认录音语言后重试。")
        }
        try Task.checkCancellation()
        do {
            let refinedText = try await refine(transcription, mode: mode, options: options)
            return ProviderResult(transcription: transcription, text: refinedText)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return ProviderResult(transcription: transcription, text: transcription,
                                  refinementWarning: error.localizedDescription)
        }
    }

    public func transcribe(audioURL: URL, options: ProcessingOptions = .init()) async throws -> String {
        guard !apiKey.isEmpty else { throw PithError.missingAPIKey }
        let baseURL = try configuration.validatedBaseURL()
        let fileData: Data
        do {
            fileData = try Data(contentsOf: audioURL)
        } catch {
            throw PithError.provider("无法读取录音文件：\(error.localizedDescription)")
        }

        let boundary = "Pith-\(UUID().uuidString)"
        var body = Data()
        appendField("model", value: configuration.transcriptionModel, boundary: boundary, to: &body)
        if let hint = options.transcriptionHint {
            appendField("prompt", value: hint, boundary: boundary, to: &body)
        }
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/mp4\r\n\r\n".utf8)
        body.append(fileData)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        var request = URLRequest(url: try endpoint("audio/transcriptions", baseURL: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data = try await send(request)
        guard let response = try? JSONDecoder().decode(TranscriptionResponse.self, from: data),
              !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PithError.invalidResponse
        }
        return response.text
    }

    public func refine(_ transcription: String, mode: DictationMode, options: ProcessingOptions = .init()) async throws -> String {
        guard !apiKey.isEmpty else { throw PithError.missingAPIKey }
        guard mode != .ask else { throw PithError.invalidConfiguration("问答需要使用独立的语音指令入口。") }
        // Keep dictated requests as source data, including quotes and embedded JSON, rather than chat instructions.
        let source = try JSONEncoder().encode(RefinementInput(transcript: transcription))
        return try await complete(system: options.systemInstruction(for: mode), source: source)
    }

    /// Separates spoken instructions from selected source text; ordinary dictation never calls this path.
    public func ask(instruction: String, context: AskContext = .init()) async throws -> AskResult {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PithError.recording("没有识别到问题，请重新说一次。")
        }
        try context.validate()
        let source = try JSONEncoder().encode(AskInput(instruction: instruction, context: context))
        let content = try await complete(system: AskResult.systemInstruction, source: source)
        return try AskResult.decode(content, context: context)
    }

    private func complete(system: String, source: Data) async throws -> String {
        guard !apiKey.isEmpty else { throw PithError.missingAPIKey }
        try Task.checkCancellation()
        let baseURL = try configuration.validatedBaseURL()
        let payload = ChatCompletionRequest(
            model: configuration.textModel,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: String(decoding: source, as: UTF8.self)),
            ],
            temperature: 0,
            thinking: baseURL.host == "api.deepseek.com" ? ThinkingConfiguration(type: "disabled") : nil
        )
        var request = URLRequest(url: try endpoint("chat/completions", baseURL: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await send(request)
        guard let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let content = response.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PithError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw PithError.invalidResponse }
            guard (200..<300).contains(httpResponse.statusCode) else {
                // Provider error bodies can echo credentials or submitted text. Never display them.
                let action: String
                switch httpResponse.statusCode {
                case 400, 422: action = "请检查模型名称和接口是否兼容。"
                case 401: action = "API Key 无效或已失效，请在设置中替换后重试。"
                case 402: action = "API 账户额度不足，请检查服务商账户。"
                case 403: action = "当前 Key 无权使用这个模型或接口，请检查服务商权限。"
                case 404: action = "未找到接口或模型，请检查 Base URL 和模型名称；DeepSeek 语音识别请选 macOS 系统。"
                case 429: action = "请求过于频繁或额度受限，请稍后重试并检查服务商配额。"
                case 500...599: action = "模型服务暂时不可用，请稍后重试。"
                default: action = "请检查服务商状态和 API 设置后重试。"
                }
                throw PithError.provider("API 请求失败（HTTP \(httpResponse.statusCode)）：\(action)")
            }
            return data
        } catch let error as PithError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PithError.provider("连接 API 失败：\(error.localizedDescription)")
        }
    }

    private func endpoint(_ path: String, baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PithError.invalidConfiguration("无法解析 API 地址。")
        }
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, path].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw PithError.invalidConfiguration("无法构造 API 请求地址。")
        }
        return url
    }

    private func appendField(_ name: String, value: String, boundary: String, to data: inout Data) {
        data.append(contentsOf: "--\(boundary)\r\n".utf8)
        data.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
        data.append(contentsOf: value.utf8)
        data.append(contentsOf: "\r\n".utf8)
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct RefinementInput: Encodable {
    let transcript: String
}

private struct AskInput: Encodable {
    let instruction: String
    let context: AskContext
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let thinking: ThinkingConfiguration?
}

private struct ThinkingConfiguration: Encodable {
    let type: String
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
