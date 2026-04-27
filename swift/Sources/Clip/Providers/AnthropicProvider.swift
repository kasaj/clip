import Foundation

/// Unified Anthropic provider — supports both direct api.anthropic.com and Azure AI Foundry.
/// Detection by URL: if baseURL contains ".azure.com", uses Azure auth (api-key header)
/// and appends ?api-version=... to the messages URL.
struct AnthropicProvider: LLMProvider {
    let model: String
    let apiKey: String
    let baseURL: String         // e.g. "https://api.anthropic.com" or Azure endpoint
    let apiVersion: String?     // For Azure: "2024-10-21"
    let temperature: Double
    let maxTokens: Int

    private var isAzure: Bool {
        baseURL.lowercased().contains(".azure.com")
    }

    private var messagesURL: URL? {
        var base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if isAzure, let ver = apiVersion {
            return URL(string: "\(base)/v1/messages?api-version=\(ver)")
        }
        return URL(string: "\(base)/v1/messages")
    }

    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    guard let url = messagesURL else {
                        continuation.finish(throwing: LLMError.missingAPIKey(baseURL))
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    if isAzure {
                        request.setValue(apiKey, forHTTPHeaderField: "api-key")
                    } else {
                        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    }
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 60

                    let body = AnthropicRequest(
                        model: model, maxTokens: maxTokens,
                        temperature: min(temperature, 1.0), system: systemPrompt,
                        messages: [.init(role: "user", content: userContent)]
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.decodingError); return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let msg = (try? JSONDecoder().decode(AnthropicErrorResponse.self, from: errorData))?.error.message
                            ?? String(data: errorData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: LLMError.httpError(http.statusCode, msg))
                        return
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if let data = payload.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(AnthropicChunk.self, from: data),
                               chunk.type == "content_block_delta",
                               chunk.delta?.type == "text_delta",
                               let text = chunk.delta?.text {
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

private struct AnthropicRequest: Encodable {
    let model: String; let maxTokens: Int; let temperature: Double
    let system: String; let messages: [Message]; let stream = true
    struct Message: Encodable { let role: String; let content: String }
    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages, stream
        case maxTokens = "max_tokens"
    }
}
private struct AnthropicChunk: Decodable {
    let type: String; let delta: Delta?
    struct Delta: Decodable { let type: String?; let text: String? }
}
private struct AnthropicErrorResponse: Decodable {
    let error: Err; struct Err: Decodable { let message: String }
}
