import Foundation

enum ProviderFactory {
    static func make(for action: Action) throws -> any LLMProvider {
        switch action.provider {

        case .azureAnthropic:
            guard let apiKey = try? KeychainStore.load(for: .azureAnthropic) else {
                throw LLMError.missingAPIKey(.azureAnthropic)
            }
            let config = ConfigStore.shared.config
            guard let endpoint = config.azureAnthropicEndpoint, !endpoint.isEmpty else {
                throw LLMError.missingAPIKey(.azureAnthropic)
            }
            let apiVersion = config.azureAnthropicAPIVersion ?? AppConfig.defaultAzureAPIVersion
            return AzureAnthropicProvider(
                model: action.model, apiKey: apiKey,
                endpoint: endpoint, apiVersion: apiVersion,
                temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .anthropic:
            guard let apiKey = try? KeychainStore.load(for: .anthropic) else {
                throw LLMError.missingAPIKey(.anthropic)
            }
            return AnthropicProvider(
                model: action.model, apiKey: apiKey,
                temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .openai:
            guard let apiKey = try? KeychainStore.load(for: .openai) else {
                throw LLMError.missingAPIKey(.openai)
            }
            return OpenAIProvider(
                model: action.model, apiKey: apiKey,
                temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .azureOpenai:
            guard let apiKey = try? KeychainStore.load(for: .azureOpenai) else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint, !endpointStr.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            let chatURL = try azureChatURL(
                deploymentBase: endpointStr,
                legacyDeployment: config.azureDeploymentName,
                apiVersion: config.azureAPIVersion ?? AppConfig.defaultAzureAPIVersion
            )
            return OpenAIProvider(
                model: action.model, apiKey: apiKey, chatURL: chatURL,
                authStyle: .apiKey, temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .azureOpenai2:
            guard let apiKey = try? KeychainStore.load(for: .azureOpenai2) else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint2, !endpointStr.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let chatURL = try azureChatURL(
                deploymentBase: endpointStr,
                legacyDeployment: config.azureDeploymentName2,
                apiVersion: config.azureAPIVersion2 ?? AppConfig.defaultAzureAPIVersion
            )
            return OpenAIProvider(
                model: action.model, apiKey: apiKey, chatURL: chatURL,
                authStyle: .apiKey, temperature: action.temperature, maxTokens: action.maxTokens
            )

        case .customOpenAI:
            let apiKey = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
            let config = ConfigStore.shared.config
            guard let urlStr = config.customOpenAIBaseURL, !urlStr.isEmpty,
                  let baseURL = URL(string: urlStr)
            else { throw LLMError.missingAPIKey(.customOpenAI) }
            return OpenAIProvider(
                model: action.model, apiKey: apiKey, baseURL: baseURL,
                temperature: action.temperature, maxTokens: action.maxTokens
            )
        }
    }

    /// Builds the full chat/completions URL for an Azure OpenAI deployment.
    private static func azureChatURL(deploymentBase: String, legacyDeployment: String?, apiVersion: String) throws -> URL {
        var base = deploymentBase.hasSuffix("/") ? String(deploymentBase.dropLast()) : deploymentBase

        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        if !base.contains("/deployments/") {
            guard let dep = legacyDeployment, !dep.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            base = "\(base)/openai/deployments/\(dep)"
        }

        var components = URLComponents(string: "\(base)/chat/completions")
        components?.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
        guard let url = components?.url else { throw LLMError.missingAPIKey(.azureOpenai) }
        return url
    }
}
