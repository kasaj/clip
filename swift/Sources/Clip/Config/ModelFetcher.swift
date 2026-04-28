import Foundation

struct FetchedModel: Identifiable {
    var id: String
    var displayName: String
    var isIncluded: Bool
    var isRecommended: Bool
    var inUseByAction: Bool
}

enum ModelFetchError: LocalizedError {
    case missingAPIKey, invalidResponse, unsupportedProvider
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:      "Chybí API klíč pro daného providera"
        case .invalidResponse:   "Neplatná odpověď ze serveru"
        case .unsupportedProvider: "Tento provider nepodporuje výpis modelů"
        }
    }
}

enum ModelFetcher {
    static func fetch(for provider: Provider) async throws -> [FetchedModel] {
        switch provider.kind {
        case .openai:    return try await fetchOpenAI(provider: provider)
        case .anthropic: return try await fetchAnthropic(provider: provider)
        case .custom:    throw ModelFetchError.unsupportedProvider
        }
    }

    private static func inUseIDs(for provider: Provider) -> Set<String> {
        Set(ConfigStore.shared.config.actions
            .filter { $0.provider == provider.id }
            .map(\.model))
    }

    // MARK: - OpenAI

    private static func fetchOpenAI(provider: Provider) async throws -> [FetchedModel] {
        let key: String
        if let k = provider.apiKey, !k.isEmpty { key = k }
        else if let k = try? KeychainStore.load(forProviderID: provider.id), !k.isEmpty { key = k }
        else { throw ModelFetchError.missingAPIKey }
        let rawBase = provider.effectiveBaseURL
        let base = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
        guard let url = URL(string: "\(base)/models") else { throw ModelFetchError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelFetchError.invalidResponse }

        struct Response: Decodable { struct Model: Decodable { let id: String; let created: Int? }; let data: [Model] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw ModelFetchError.invalidResponse }

        let excluded = ["embedding", "tts", "whisper", "dall-e", "babbage", "davinci",
                        "ada", "curie", "instruct", "realtime", "audio", "transcribe",
                        "moderation", "search", "similarity", "text-"]
        let inUse = inUseIDs(for: provider)
        let recommended = "gpt-4o"
        var models = decoded.data
            .filter { m in !excluded.contains(where: { m.id.lowercased().contains($0) }) }
            .sorted { ($0.created ?? 0) > ($1.created ?? 0) }
            .map { m in FetchedModel(id: m.id, displayName: m.id, isIncluded: true,
                                     isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id)) }
        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    // MARK: - Anthropic

    private static func fetchAnthropic(provider: Provider) async throws -> [FetchedModel] {
        let key: String
        if let k = provider.apiKey, !k.isEmpty { key = k }
        else if let k = try? KeychainStore.load(forProviderID: provider.id), !k.isEmpty { key = k }
        else { throw ModelFetchError.missingAPIKey }
        // Use direct api.anthropic.com for model listing even for Azure-proxied providers
        let rawBase = provider.effectiveBaseURL.lowercased().contains(".azure.com")
            ? "https://api.anthropic.com" : provider.effectiveBaseURL
        let trimmed = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
        guard let url = URL(string: "\(trimmed)/v1/models") else { throw ModelFetchError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelFetchError.invalidResponse }

        struct Response: Decodable { struct Model: Decodable { let id: String; let display_name: String? }; let data: [Model] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw ModelFetchError.invalidResponse }

        let inUse = inUseIDs(for: provider)
        let recommended = "claude-sonnet-4-6"
        var models = decoded.data.map { m in
            FetchedModel(id: m.id, displayName: m.display_name ?? m.id, isIncluded: true,
                         isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id))
        }
        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    private static func appendMissingInUse(_ inUse: Set<String>, recommended: String?, into models: inout [FetchedModel]) {
        let fetched = Set(models.map(\.id))
        for id in inUse where !fetched.contains(id) {
            models.append(FetchedModel(id: id, displayName: id, isIncluded: true,
                                       isRecommended: id == recommended, inUseByAction: true))
        }
    }
}
