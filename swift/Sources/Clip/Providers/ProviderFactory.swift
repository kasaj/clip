import Foundation

enum ProviderFactory {

    // MARK: - Make streaming provider

    static func make(for action: Action) throws -> any LLMProvider {
        let config = ConfigStore.shared.config

        // Action has no provider assigned yet
        guard !action.provider.isEmpty else {
            throw LLMError.missingAPIKey("Akce nemá přiřazeného providera — nastav ho v Nastavení → Akce")
        }

        // Look up provider by UUID
        guard let uuid = UUID(uuidString: action.provider),
              let provider = config.providers.first(where: { $0.id == uuid }) else {
            throw LLMError.missingAPIKey("Provider nenalezen — zkontroluj nastavení akce nebo přidej provider v Nastavení → Providery")
        }

        return try makeProvider(provider: provider, model: action.model,
                                temperature: action.temperature, maxTokens: action.maxTokens)
    }

    // MARK: - Test a provider (sends one minimal message)

    static func test(provider: Provider) async throws -> String {
        let llm = try makeProvider(provider: provider, model: bestModel(for: provider),
                                   temperature: 0.0, maxTokens: 64)
        var response = ""
        for try await chunk in llm.stream(systemPrompt: "You are a test assistant.", userContent: "Reply with exactly: OK") {
            response += chunk
            if response.count > 200 { break }
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.decodingError }
        return trimmed
    }

    // MARK: - Private helpers

    private static func makeProvider(provider: Provider, model: String,
                                     temperature: Double, maxTokens: Int) throws -> any LLMProvider {
        guard let apiKey = try? KeychainStore.load(forProviderID: provider.id), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(provider.name)
        }

        switch provider.kind {
        case .anthropic:
            guard !provider.baseURL.isEmpty else {
                throw LLMError.missingAPIKey("\(provider.name) — Base URL není nastavena")
            }
            return AnthropicProvider(
                model: model.isEmpty ? "claude-sonnet-4-6" : model,
                apiKey: apiKey,
                baseURL: provider.baseURL,
                apiVersion: provider.apiVersion,
                temperature: temperature, maxTokens: maxTokens
            )

        case .openai, .custom:
            guard !provider.baseURL.isEmpty, let baseURL = URL(string: provider.baseURL) else {
                throw LLMError.missingAPIKey("\(provider.name) — Base URL není nastavena")
            }
            let isAzure = provider.baseURL.lowercased().contains(".azure.com")
            return OpenAIProvider(
                model: model.isEmpty ? "gpt-4o" : model,
                apiKey: apiKey, baseURL: baseURL,
                authStyle: isAzure ? .apiKey : .bearer,
                temperature: temperature, maxTokens: maxTokens
            )
        }
    }

    private static func bestModel(for provider: Provider) -> String {
        let presets = provider.effectiveModels(using: ConfigStore.shared.config.modelPresets)
        return presets.first(where: \.isRecommended)?.id ?? presets.first?.id ?? ""
    }
}
