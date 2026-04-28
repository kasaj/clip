import Foundation

/// Provider for the OpenAI Responses API endpoint  (/responses).
/// Used by Azure AI Foundry project-level endpoints and OpenAI o-series models.
///
/// Request format differs from Chat Completions:
///   • "input" array instead of "messages"
///   • system prompt goes inside "input", not at top-level
///   • streaming event type: response.output_text.delta  → delta: String
struct ResponsesAPIProvider: LLMProvider {
    let model: String
    let apiKey: String
    let endpointURL: URL        // full URL ending with /responses
    let authStyle: OpenAIAuthStyle
    let temperature: Double
    let maxTokens: Int

    func stream(systemPrompt: String,
                userContent: String,
                imageData: Data?,
                mimeType: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    var request = URLRequest(url: endpointURL)
                    request.httpMethod = "POST"
                    switch authStyle {
                    case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    case .apiKey: request.setValue(apiKey,             forHTTPHeaderField: "api-key")
                    }
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    // Build input array — system + user (image if provided)
                    var userContent_: Any
                    if let imgData = imageData, let mime = mimeType {
                        var blocks: [[String: Any]] = [[
                            "type": "input_image",
                            "image_url": "data:\(mime);base64,\(imgData.base64EncodedString())"
                        ]]
                        if !userContent.isEmpty {
                            blocks.append(["type": "input_text", "text": userContent])
                        }
                        userContent_ = blocks
                    } else {
                        userContent_ = userContent
                    }

                    var input: [[String: Any]] = []
                    if !systemPrompt.isEmpty {
                        input.append(["role": "system", "content": systemPrompt])
                    }
                    input.append(["role": "user", "content": userContent_])

                    var body: [String: Any] = [
                        "model": model,
                        "input": input,
                        "stream": true
                    ]
                    if maxTokens > 0 { body["max_output_tokens"] = maxTokens }

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.decodingError); return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errData = Data()
                        for try await byte in bytes { errData.append(byte) }
                        let msg = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: errData))?.error.message
                            ?? String(data: errData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: LLMError.httpError(http.statusCode, msg))
                        return
                    }

                    // SSE: look for response.output_text.delta events
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        let type_ = json["type"] as? String ?? ""
                        // Primary: response.output_text.delta
                        if type_ == "response.output_text.delta",
                           let delta = json["delta"] as? String {
                            continuation.yield(delta)
                        }
                        // Fallback: some Azure variants nest under "text"
                        else if type_.hasSuffix(".delta"),
                                let delta = json["text"] as? String {
                            continuation.yield(delta)
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

private struct OpenAIErrorEnvelope: Decodable {
    let error: Msg
    struct Msg: Decodable { let message: String }
}
