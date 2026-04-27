import Foundation

enum ProviderFactory {
    static func make(for action: Action) throws -> any LLMProvider {
        let config = ConfigStore.shared.config

        // Look up provider by UUID
        guard let uuid = UUID(uuidString: action.provider),
              let provider = config.providers.first(where: { $0.id == uuid }) else {
            throw LLMError.missingAPIKey("Provider ID '\(action.provider)' nenalezen — zkontroluj nastavení agenta")
        }

        // Load API key from Keychain
        guard let apiKey = try? KeychainStore.load(forProviderID: provider.id),
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(provider.name)
        }

        switch provider.kind {

        case .anthropic:
            guard !provider.baseURL.isEmpty else {
                throw LLMError.missingAPIKey("\(provider.name) — URL není nastavena")
            }
            return AnthropicProvider(
                model: action.model, apiKey: apiKey,
                baseURL: provider.baseURL, apiVersion: provider.apiVersion,
                temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .openai, .custom:
            guard !provider.baseURL.isEmpty, let baseURL = URL(string: provider.baseURL) else {
                throw LLMError.missingAPIKey("\(provider.name) — URL není nastavena")
            }
            // Auto-detect Azure OpenAI: uses api-key header instead of Bearer
            let isAzureOpenAI = provider.baseURL.lowercased().contains(".azure.com")
            return OpenAIProvider(
                model: action.model, apiKey: apiKey, baseURL: baseURL,
                authStyle: isAzureOpenAI ? .apiKey : .bearer,
                temperature: action.temperature, maxTokens: action.maxTokens
            )
        }
    }
}
