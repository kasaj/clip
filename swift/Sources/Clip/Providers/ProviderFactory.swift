import Foundation

enum ProviderFactory {

    // MARK: - Make streaming provider

    static func make(for action: Action) throws -> any LLMProvider {
        let config = ConfigStore.shared.config

        // Resolve provider: match by string ID, or auto-pick if exactly one exists
        let provider: Provider
        if !action.provider.isEmpty,
           let found = config.providers.first(where: { $0.id == action.provider }) {
            provider = found
        } else if config.providers.count == 1 {
            provider = config.providers[0]
        } else if config.providers.isEmpty {
            throw LLMError.missingAPIKey("Žádný provider není nakonfigurován — přidej ho v Nastavení → Providery")
        } else {
            throw LLMError.missingAPIKey("Akce nemá přiřazen provider — nastav ho v Nastavení → Akce")
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
        // API key: flat JSON field first, then Keychain
        let apiKey: String
        if let k = provider.apiKey, !k.isEmpty { apiKey = k }
        else if let k = try? KeychainStore.load(forProviderID: provider.id), !k.isEmpty { apiKey = k }
        else {
            throw LLMError.missingAPIKey("\(provider.name) — API klíč chybí (Nastavení → Providery → API Klíč → Uložit)")
        }

        // Effective model: action override > provider model field > kind default
        let providerModel = provider.model ?? ""
        let resolvedModel = model.isEmpty ? providerModel : model

        switch provider.kind {

        // MARK: Anthropic
        case .anthropic:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty else {
                throw LLMError.missingAPIKey("\(provider.name) — URL není nastavena")
            }
            return AnthropicProvider(
                model: resolvedModel.isEmpty ? "claude-sonnet-4-20250514" : resolvedModel,
                apiKey: apiKey,
                baseURL: base,
                apiVersion: provider.effectiveApiVersion,
                temperature: temperature,
                maxTokens: maxTokens
            )

        // MARK: OpenAI (direct)
        case .openai:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty, let parsedURL = URL(string: base) else {
                throw LLMError.missingAPIKey("\(provider.name) — URL není nastavena")
            }
            let finalModel = resolvedModel.isEmpty ? "gpt-4o" : resolvedModel
            let lower = base.lowercased()
            if lower.hasSuffix("/responses") {
                return ResponsesAPIProvider(model: finalModel, apiKey: apiKey,
                                            endpointURL: parsedURL, authStyle: .bearer,
                                            temperature: temperature, maxTokens: maxTokens)
            } else if lower.hasSuffix("/chat/completions") {
                return OpenAIProvider(model: finalModel, apiKey: apiKey,
                                      chatURL: parsedURL, authStyle: .bearer,
                                      temperature: temperature, maxTokens: maxTokens)
            } else {
                return OpenAIProvider(model: finalModel, apiKey: apiKey,
                                      baseURL: parsedURL, authStyle: .bearer,
                                      temperature: temperature, maxTokens: maxTokens)
            }

        // MARK: Custom / Azure AI (any OpenAI-compatible endpoint)
        case .custom:
            let base = provider.effectiveBaseURL
            guard !base.isEmpty, !base.hasPrefix("https://RESOURCE") else {
                throw LLMError.missingAPIKey("\(provider.name) — URL není nastavena (nahraď placeholder v Nastavení → Providery)")
            }
            guard let _ = URL(string: base) else {
                throw LLMError.missingAPIKey("\(provider.name) — neplatná URL")
            }
            guard !resolvedModel.isEmpty, !resolvedModel.hasPrefix("DEPLOYMENT") else {
                throw LLMError.missingAPIKey("\(provider.name) — Model/Deployment není nastaven (Nastavení → Providery → Model)")
            }

            let lower = base.lowercased()
            // Azure: any URL containing .azure.com uses api-key header auth
            let isAzure = lower.contains(".azure.com")
            let auth: OpenAIAuthStyle = isAzure ? .apiKey : .bearer

                // --- URL strategy ---
            // Parse path separately so query strings (e.g. ?api-version=...) don't break detection
            let urlPath = (URLComponents(string: base)?.path ?? base).lowercased()

            let isResponsesEndpoint    = urlPath.hasSuffix("/responses")
            let isChatEndpoint         = urlPath.hasSuffix("/chat/completions")
            let isFullEndpoint         = isResponsesEndpoint || isChatEndpoint
            // OpenAI-compatible base: has /v1 suffix → just append /chat/completions
            let isOpenAICompatibleBase = lower.hasSuffix("/v1") || urlPath.hasSuffix("/openai/v1")
                                         || urlPath.contains("/openai/v1")
            // Traditional Azure: bare hostname or project URL, no /v1 and no /deployments/
            let isAzureDeploymentBase  = isAzure && !isFullEndpoint && !isOpenAICompatibleBase
                                         && !urlPath.contains("/deployments/")

            let chatURLStr: String
            if isFullEndpoint {
                // Already a full endpoint URL — use directly
                chatURLStr = base
            } else if isAzureDeploymentBase {
                // Construct: {base}/openai/deployments/{model}/chat/completions?api-version={ver}
                let b = base.hasSuffix("/") ? base : base + "/"
                let ver = provider.apiVersion ?? "2024-02-01"
                chatURLStr = "\(b)openai/deployments/\(resolvedModel)/chat/completions?api-version=\(ver)"
            } else {
                // baseURL style: OpenAIProvider will append /chat/completions
                chatURLStr = base
            }

            guard let parsedURL = URL(string: chatURLStr) else {
                throw LLMError.missingAPIKey("\(provider.name) — neplatná URL: \(chatURLStr)")
            }

            // Route to correct provider implementation
            let finalPath = (URLComponents(string: chatURLStr)?.path ?? chatURLStr).lowercased()
            if finalPath.hasSuffix("/responses") {
                return ResponsesAPIProvider(model: resolvedModel, apiKey: apiKey,
                                            endpointURL: parsedURL, authStyle: auth,
                                            temperature: temperature, maxTokens: maxTokens)
            } else if finalPath.hasSuffix("/chat/completions") {
                return OpenAIProvider(model: resolvedModel, apiKey: apiKey,
                                      chatURL: parsedURL, authStyle: auth,
                                      temperature: temperature, maxTokens: maxTokens)
            } else {
                // baseURL → OpenAIProvider appends /chat/completions
                return OpenAIProvider(model: resolvedModel, apiKey: apiKey,
                                      baseURL: parsedURL, authStyle: auth,
                                      temperature: temperature, maxTokens: maxTokens)
            }
        }
    }

    private static func bestModel(for provider: Provider) -> String {
        let presets = provider.effectiveModels(using: ConfigStore.shared.config.modelPresets)
        return presets.first(where: \.isRecommended)?.id ?? presets.first?.id ?? provider.model ?? ""
    }
}
