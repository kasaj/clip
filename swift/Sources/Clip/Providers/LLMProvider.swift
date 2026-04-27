import Foundation

protocol LLMProvider: Sendable {
    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error>
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(String)  // provider name or description
    case httpError(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): "Chybí API klíč nebo URL pro provider \"\(name)\". Nastav ho v Nastavení → Providery."
        case .httpError(let code, let msg): "API chyba \(code): \(msg)"
        case .networkError(let err):        "Síťová chyba: \(err.localizedDescription)"
        case .decodingError:                "Chyba při zpracování odpovědi"
        }
    }
}
