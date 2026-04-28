import Foundation

enum OpenAIAuthStyle {
    case bearer   // Authorization: Bearer {key}  — OpenAI, custom
    case apiKey   // api-key: {key}               — Azure OpenAI
}

struct OpenAIProvider: LLMProvider {
    let model: String
    let apiKey: String
    let chatURL: URL
    let authStyle: OpenAIAuthStyle
    let temperature: Double
    let maxTokens: Int

    init(model: String, apiKey: String,
         baseURL: URL = URL(string: "https://api.openai.com/v1")!,
         chatURL: URL? = nil,
         authStyle: OpenAIAuthStyle = .bearer,
         temperature: Double = 0.7, maxTokens: Int = 4096) {
        self.model = model
        self.apiKey = apiKey
        self.chatURL = chatURL ?? baseURL.appendingPathComponent("chat/completions")
        self.authStyle = authStyle
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func stream(systemPrompt: String,
                userContent: String,
                imageData: Data?,
                mimeType: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    var request = URLRequest(url: chatURL)
                    request.httpMethod = "POST"
                    switch authStyle {
                    case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    case .apiKey: request.setValue(apiKey,             forHTTPHeaderField: "api-key")
                    }
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    if let imgData = imageData, let mime = mimeType {
                        // Multimodal: image_url block + optional text block
                        let dataURL = "data:\(mime);base64,\(imgData.base64EncodedString())"
                        var userBlocks: [OpenAIContentBlock] = [.image(url: dataURL)]
                        if !userContent.isEmpty { userBlocks.append(.text(userContent)) }

                        let body = OpenAIMultimodalRequest(
                            model: model,
                            messages: [
                                .system(systemPrompt),
                                .user(userBlocks)
                            ],
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                        request.httpBody = try JSONEncoder().encode(body)
                    } else {
                        // Text-only
                        let body = OpenAITextRequest(
                            model: model,
                            messages: [
                                .init(role: "system", content: systemPrompt),
                                .init(role: "user",   content: userContent)
                            ],
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                        request.httpBody = try JSONEncoder().encode(body)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.decodingError); return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let message = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: errorData))?.error.message
                            ?? String(data: errorData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: LLMError.httpError(http.statusCode, message))
                        return
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }
                            if let data = payload.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                               let text = chunk.choices.first?.delta.content {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Text-only request

private struct OpenAITextRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool = true
    struct Message: Encodable { let role: String; let content: String }
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

// MARK: - Multimodal request

private struct OpenAIMultimodalRequest: Encodable {
    let model: String
    let messages: [OpenAIMultimodalMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool = true
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private enum OpenAIMultimodalMessage: Encodable {
    case system(String)
    case user([OpenAIContentBlock])

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .system(let text):
            try c.encode("system", forKey: .role)
            try c.encode(text,     forKey: .content)
        case .user(let blocks):
            try c.encode("user",   forKey: .role)
            try c.encode(blocks,   forKey: .content)
        }
    }
    enum CK: String, CodingKey { case role, content }
}

private enum OpenAIContentBlock: Encodable {
    case text(String)
    case image(url: String)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t,      forKey: .text)
        case .image(let url):
            try c.encode("image_url", forKey: .type)
            try c.encode(["url": url], forKey: .imageURL)
        }
    }
    enum CK: String, CodingKey { case type, text, imageURL = "image_url" }
}

// MARK: - Shared response types

private struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        struct Delta: Decodable { let content: String? }
    }
}
private struct OpenAIErrorResponse: Decodable {
    let error: APIError
    struct APIError: Decodable { let message: String }
}
