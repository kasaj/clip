import Foundation

protocol LLMProvider: Sendable {
    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error>
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(ProviderType)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            switch provider {
            case .azureAnthropic: "Chybí API klíč nebo endpoint pro Claude (Azure). Přidej ho v Nastavení → Providery."
            case .anthropic:      "Chybí API klíč pro Anthropic (Claude). Přidej ho v Nastavení → Providery."
            case .azureOpenai:    "Chybí API klíč nebo konfigurace pro ChatGPT (Azure) slot 1. Přidej ho v Nastavení → Providery."
            case .azureOpenai2:   "Chybí API klíč nebo konfigurace pro ChatGPT (Azure) slot 2. Přidej ho v Nastavení → Providery."
            case .openai:         "Chybí API klíč pro OpenAI. Přidej ho v Nastavení → Providery."
            case .customOpenAI:   "Chybí Base URL pro vlastní OpenAI-compatible provider. Nakonfiguruj ho v Nastavení → Providery."
            }
        case .httpError(let code, let message): "API chyba \(code): \(message)"
        case .networkError(let error):          "Síťová chyba: \(error.localizedDescription)"
        case .decodingError:                    "Chyba při zpracování odpovědi"
        }
    }
}
