import Foundation

protocol LLMProvider: Sendable {
    /// Stream a response. Pass `imageData` + `mimeType` for vision/multimodal requests.
    func stream(systemPrompt: String,
                userContent: String,
                imageData: Data?,
                mimeType: String?) -> AsyncThrowingStream<String, Error>
}

extension LLMProvider {
    /// Convenience — text-only.
    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        stream(systemPrompt: systemPrompt, userContent: userContent, imageData: nil, mimeType: nil)
    }
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(String)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): "Missing API key or URL for provider \"\(name)\". Configure it in Settings → Providers."
        case .httpError(let code, let msg): "API error \(code): \(msg)"
        case .networkError(let err):        "Network error: \(err.localizedDescription)"
        case .decodingError:                "Failed to decode API response"
        }
    }
}
