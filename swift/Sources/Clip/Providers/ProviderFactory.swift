import Foundation

enum ProviderFactory {

    // MARK: - Make streaming provider

    static func make(for action: Action) throws -> any LLMProvider {
        let config = ConfigStore.shared.config

        // Resolve provider: use action's assigned provider, or auto-pick if exactly one exists
        let provider: Provider
        if !action.provider.isEmpty,
           let uuid = UUID(uuidString: action.provider),
           let found = config.providers.first(where: { $0.id == uuid }) {
            provider = found
        } else if config.providers.count == 1 {
            // Convenience: auto-assign when there's exactly one provider
            provider = config.providers[0]
        } else if config.providers.isEmpty {
            throw LLMError.missingAPIKey("No providers configured — add one in Settings → Providers")
        } else {
            throw LLMError.missingAPIKey("No provider assigned — open Settings → Actions and pick a provider for this action")
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
            let fallback = provider.defaultModel.isEmpty ? "claude-sonnet-4-6" : provider.defaultModel
            return AnthropicProvider(
                model: model.isEmpty ? fallback : model,
                apiKey: apiKey,
                baseURL: provider.baseURL,
                apiVersion: provider.apiVersion,
                temperature: temperature, maxTokens: maxTokens
            )

        case .openai, .custom:
            guard !provider.baseURL.isEmpty, let parsedURL = URL(string: provider.baseURL) else {
                throw LLMError.missingAPIKey("\(provider.name) — Base URL není nastavena")
            }
            let urlLower = provider.baseURL.lowercased()
            let isAzure = urlLower.contains(".azure.com") || urlLower.contains(".services.ai.azure.com")
            let auth: OpenAIAuthStyle = isAzure ? .apiKey : .bearer
            let fallback = provider.defaultModel.isEmpty ? "gpt-4o" : provider.defaultModel
            let effectiveModel = model.isEmpty ? fallback : model

            // Detect full endpoint URLs so Clip doesn't append /chat/completions wrongly:
            //   …/responses        → OpenAI Responses API (Azure AI Foundry project endpoints)
            //   …/chat/completions → standard Chat Completions used directly
            //   anything else      → treat as base URL, append /chat/completions
            if urlLower.hasSuffix("/responses") {
                return ResponsesAPIProvider(
                    model: effectiveModel, apiKey: apiKey,
                    endpointURL: parsedURL, authStyle: auth,
                    temperature: temperature, maxTokens: maxTokens
                )
            } else if urlLower.hasSuffix("/chat/completions") {
                return OpenAIProvider(
                    model: effectiveModel, apiKey: apiKey,
                    chatURL: parsedURL, authStyle: auth,
                    temperature: temperature, maxTokens: maxTokens
                )
            } else {
                return OpenAIProvider(
                    model: effectiveModel, apiKey: apiKey,
                    baseURL: parsedURL, authStyle: auth,
                    temperature: temperature, maxTokens: maxTokens
                )
            }
        }
    }

    private static func bestModel(for provider: Provider) -> String {
        let presets = provider.effectiveModels(using: ConfigStore.shared.config.modelPresets)
        return presets.first(where: \.isRecommended)?.id ?? presets.first?.id ?? ""
    }
}
