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
        // API key: JSON auth.api_key takes priority, then Keychain
        let apiKey: String
        if let k = provider.auth?.apiKey, !k.isEmpty { apiKey = k }
        else if let k = try? KeychainStore.load(forProviderID: provider.id), !k.isEmpty { apiKey = k }
        else { throw LLMError.missingAPIKey(provider.name) }

        // Effective model: action override > provider options > kind default
        let providerModel = provider.options?.model ?? ""
        let resolvedModel = model.isEmpty ? providerModel : model

        switch provider.kind {

        case .anthropic:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty else {
                throw LLMError.missingAPIKey("\(provider.name) — endpoint.base_url není nastavena")
            }
            return AnthropicProvider(
                model: resolvedModel.isEmpty ? "claude-sonnet-4-6" : resolvedModel,
                apiKey: apiKey, baseURL: base, apiVersion: provider.effectiveApiVersion,
                temperature: temperature, maxTokens: maxTokens
            )

        case .openai, .custom:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty, let parsedURL = URL(string: base) else {
                throw LLMError.missingAPIKey("\(provider.name) — endpoint.base_url není nastavena")
            }
            let lower = base.lowercased()
            let isAzure = lower.contains(".azure.com") || lower.contains(".services.ai.azure.com")
            let auth: OpenAIAuthStyle = isAzure ? .apiKey : .bearer
            let finalModel = resolvedModel.isEmpty ? "gpt-4o" : resolvedModel
            if lower.hasSuffix("/responses") {
                return ResponsesAPIProvider(model: finalModel, apiKey: apiKey,
                                            endpointURL: parsedURL, authStyle: auth,
                                            temperature: temperature, maxTokens: maxTokens)
            } else if lower.hasSuffix("/chat/completions") {
                return OpenAIProvider(model: finalModel, apiKey: apiKey,
                                      chatURL: parsedURL, authStyle: auth,
                                      temperature: temperature, maxTokens: maxTokens)
            } else {
                return OpenAIProvider(model: finalModel, apiKey: apiKey,
                                      baseURL: parsedURL, authStyle: auth,
                                      temperature: temperature, maxTokens: maxTokens)
            }

        case .azureOpenAI:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty else {
                throw LLMError.missingAPIKey("\(provider.name) — endpoint.base_url není nastavena")
            }
            let lower = base.lowercased()
            // Deployment name is used as model identifier for Azure
            let deployment = provider.endpoint?.deploymentName ?? ""
            let finalModel = deployment.isEmpty ? (resolvedModel.isEmpty ? "gpt-4o" : resolvedModel) : deployment

            // Build full chat URL if deployment_name given and base is not already a full path
            let fullURLStr: String
            if lower.hasSuffix("/responses") || lower.hasSuffix("/chat/completions") {
                fullURLStr = base   // already a complete endpoint URL
            } else if !deployment.isEmpty && !lower.contains("/deployments/") {
                let b = base.hasSuffix("/") ? base : base + "/"
                let ver = provider.endpoint?.apiVersion ?? "2024-02-01"
                fullURLStr = "\(b)openai/deployments/\(deployment)/chat/completions?api-version=\(ver)"
            } else {
                fullURLStr = base
            }

            guard let parsedURL = URL(string: fullURLStr) else {
                throw LLMError.missingAPIKey("\(provider.name) — neplatná Azure URL")
            }
            if lower.hasSuffix("/responses") {
                return ResponsesAPIProvider(model: finalModel, apiKey: apiKey,
                                            endpointURL: parsedURL, authStyle: .apiKey,
                                            temperature: temperature, maxTokens: maxTokens)
            } else {
                return OpenAIProvider(model: finalModel, apiKey: apiKey,
                                      chatURL: parsedURL, authStyle: .apiKey,
                                      temperature: temperature, maxTokens: maxTokens)
            }
        }
    }

    private static func bestModel(for provider: Provider) -> String {
        let presets = provider.effectiveModels(using: ConfigStore.shared.config.modelPresets)
        return presets.first(where: \.isRecommended)?.id ?? presets.first?.id ?? ""
    }
}
