import Carbon
import Foundation

// MARK: - ModelPreset

struct ModelPreset: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var isRecommended: Bool
    init(id: String, displayName: String, isRecommended: Bool = false) {
        self.id = id; self.displayName = displayName; self.isRecommended = isRecommended
    }
}

// MARK: - ProviderKind

/// Three provider kinds — Azure AI goes under .custom (auto-detected by URL domain).
enum ProviderKind: String, Codable, CaseIterable {
    case anthropic  // Anthropic Messages API
    case openai     // OpenAI Chat Completions (direct)
    case custom     // Any OpenAI-compatible endpoint: Azure AI, local, etc.

    // Custom decoder so "azure_openai" (legacy) gracefully falls back to .custom
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProviderKind(rawValue: raw) ?? .custom
    }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai:    "OpenAI"
        case .custom:    "Vlastní / Azure AI"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openai:    "https://api.openai.com/v1"
        case .custom:    ""
        }
    }

    var presetModels: [ModelPreset] {
        switch self {
        case .anthropic:
            [
                .init(id: "claude-sonnet-4-20250514", displayName: "claude-sonnet-4.5", isRecommended: true),
                .init(id: "claude-opus-4-5",          displayName: "claude-opus-4.5"),
                .init(id: "claude-haiku-4-5",         displayName: "claude-haiku-4.5"),
            ]
        case .openai:
            [
                .init(id: "gpt-4o",      displayName: "gpt-4o", isRecommended: true),
                .init(id: "gpt-4o-mini", displayName: "gpt-4o-mini"),
                .init(id: "o4-mini",     displayName: "o4-mini"),
                .init(id: "o3",          displayName: "o3"),
            ]
        case .custom:
            []
        }
    }
}

// MARK: - Provider defaults (runtime/config defaults per provider)

struct ProviderDefaults: Codable, Equatable, Hashable {
    var temperature: Double?
    var maxTokens: Int?
    var timeoutSeconds: Int?
    enum CodingKeys: String, CodingKey {
        case temperature; case maxTokens = "max_tokens"; case timeoutSeconds = "timeout_seconds"
    }
}

// MARK: - Legacy nested sub-structs (used only for backward-compat migration in decoder)

private struct _LegacyAuth: Decodable {
    var apiKey: String?
    enum CodingKeys: String, CodingKey { case apiKey = "api_key" }
}
private struct _LegacyEndpoint: Decodable {
    var baseURL: String?; var apiVersion: String?; var deploymentName: String?
    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"; case apiVersion = "api_version"; case deploymentName = "deployment_name"
    }
}
private struct _LegacyOptions: Decodable {
    var model: String?; var maxTokens: Int?; var temperature: Double?; var timeoutSeconds: Int?
    enum CodingKeys: String, CodingKey {
        case model; case maxTokens = "max_tokens"; case temperature; case timeoutSeconds = "timeout_seconds"
    }
}

// MARK: - Provider

/// A user-managed provider record.
/// API key can live in auth.api_key (providers.json) or Keychain (entered via Settings).
/// A user-managed provider record.
/// JSON format (flat): id, name, provider, enabled, default, api_key, base_url,
///   model, deployment_name, api_version, organization_id, defaults{temperature,max_tokens,timeout_seconds}
struct Provider: Identifiable, Codable, Equatable, Hashable {
    var id: String              // any string — UUID, "anthropic-main", etc.
    var name: String
    var kind: ProviderKind
    var enabled: Bool
    var isDefault: Bool
    // Flat connection fields
    var apiKey: String?
    var baseURL: String?
    var model: String?
    var deploymentName: String?
    var apiVersion: String?
    var organizationId: String?
    var defaults: ProviderDefaults?

    init(id: String = UUID().uuidString, name: String, kind: ProviderKind,
         enabled: Bool = true, isDefault: Bool = false,
         apiKey: String? = nil, baseURL: String? = nil, model: String? = nil,
         deploymentName: String? = nil, apiVersion: String? = nil,
         organizationId: String? = nil, defaults: ProviderDefaults? = nil) {
        self.id = id; self.name = name; self.kind = kind
        self.enabled = enabled; self.isDefault = isDefault
        self.apiKey = apiKey; self.baseURL = baseURL; self.model = model
        self.deploymentName = deploymentName; self.apiVersion = apiVersion
        self.organizationId = organizationId; self.defaults = defaults
    }

    // Decoder — accepts new flat format AND migrates old nested format (v0.28–0.30)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id: accept UUID string OR custom string like "anthropic-main"
        id        = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name      = try c.decode(String.self, forKey: .name)
        enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled)   ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        defaults  = try c.decodeIfPresent(ProviderDefaults.self, forKey: .defaults)
        // Kind: "provider" key (new) or "kind" key (old)
        if let k = try c.decodeIfPresent(ProviderKind.self, forKey: .kind)       { kind = k }
        else if let k = try c.decodeIfPresent(ProviderKind.self, forKey: .legacyKind) { kind = k }
        else { kind = .custom }
        // Flat fields (new format)
        apiKey         = try c.decodeIfPresent(String.self, forKey: .apiKey)
        baseURL        = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model          = try c.decodeIfPresent(String.self, forKey: .model)
        deploymentName = try c.decodeIfPresent(String.self, forKey: .deploymentName)
        apiVersion     = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        organizationId = try c.decodeIfPresent(String.self, forKey: .organizationId)
        // Migration: nested auth/endpoint/options (v0.28–0.30)
        if apiKey == nil,
           let auth = try c.decodeIfPresent(_LegacyAuth.self, forKey: .legacyAuth),
           auth.apiKey?.isEmpty == false { apiKey = auth.apiKey }
        if let ep = try c.decodeIfPresent(_LegacyEndpoint.self, forKey: .legacyEndpoint) {
            if baseURL == nil,        let v = ep.baseURL,        !v.isEmpty { baseURL = v }
            if deploymentName == nil, let v = ep.deploymentName, !v.isEmpty { deploymentName = v }
            if apiVersion == nil,     let v = ep.apiVersion,     !v.isEmpty { apiVersion = v }
        }
        if let opts = try c.decodeIfPresent(_LegacyOptions.self, forKey: .legacyOptions) {
            if model == nil,    let v = opts.model, !v.isEmpty { model = v }
            if defaults == nil { defaults = ProviderDefaults(temperature: opts.temperature,
                                                             maxTokens: opts.maxTokens,
                                                             timeoutSeconds: opts.timeoutSeconds) }
        }
        // Very old flat format (before v0.28)
        if baseURL == nil,    let v = try c.decodeIfPresent(String.self, forKey: .veryOldBaseURL),    !v.isEmpty { baseURL = v }
        if apiVersion == nil, let v = try c.decodeIfPresent(String.self, forKey: .veryOldApiVersion), !v.isEmpty { apiVersion = v }
        if model == nil,      let v = try c.decodeIfPresent(String.self, forKey: .veryOldModel),      !v.isEmpty { model = v }
        // Normalize: empty string → nil
        if apiKey?.isEmpty         == true { apiKey = nil }
        if baseURL?.isEmpty        == true { baseURL = nil }
        if model?.isEmpty          == true { model = nil }
        if deploymentName?.isEmpty == true { deploymentName = nil }
        if apiVersion?.isEmpty     == true { apiVersion = nil }
        if organizationId?.isEmpty == true { organizationId = nil }
        // Azure migration: old azure_openai used deploymentName as the model identifier;
        // for .custom type, model is the primary identifier → promote deploymentName → model
        if kind == .custom, model == nil, let dep = deploymentName {
            model = dep
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(name,      forKey: .name)
        try c.encode(kind,      forKey: .kind)       // writes "provider"
        try c.encode(enabled,   forKey: .enabled)
        try c.encode(isDefault, forKey: .isDefault)  // writes "default"
        try c.encodeIfPresent(apiKey,         forKey: .apiKey)
        try c.encodeIfPresent(organizationId, forKey: .organizationId)
        try c.encodeIfPresent(baseURL,        forKey: .baseURL)
        try c.encodeIfPresent(deploymentName, forKey: .deploymentName)
        try c.encodeIfPresent(apiVersion,     forKey: .apiVersion)
        try c.encodeIfPresent(model,          forKey: .model)
        try c.encodeIfPresent(defaults,       forKey: .defaults)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, defaults, model
        case kind           = "provider"
        case isDefault      = "default"
        case apiKey         = "api_key"
        case baseURL        = "base_url"
        case deploymentName = "deployment_name"
        case apiVersion     = "api_version"
        case organizationId = "organization_id"
        // Legacy nested (v0.28–0.30)
        case legacyKind     = "kind"
        case legacyAuth     = "auth"
        case legacyEndpoint = "endpoint"
        case legacyOptions  = "options"
        // Very old flat (before v0.28)
        case veryOldBaseURL    = "baseURL"
        case veryOldApiVersion = "apiVersion"
        case veryOldModel      = "defaultModel"
    }

    // Computed convenience
    var effectiveBaseURL: String    { baseURL ?? kind.defaultBaseURL }
    var effectiveApiVersion: String? { apiVersion }
    var effectiveModel: String      { model ?? "" }

    func effectiveModels(using presets: [String: [ModelPreset]]) -> [ModelPreset] {
        let stored = presets[id] ?? []
        return stored.isEmpty ? kind.presetModels : stored
    }

    // MARK: - Template factory

    static func template(kind: ProviderKind, name: String = "") -> Provider {
        let n = name.isEmpty ? kind.displayName : name
        let def = ProviderDefaults(temperature: 0.7, maxTokens: 4096, timeoutSeconds: 60)
        switch kind {
        case .anthropic:
            return Provider(name: n, kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude-sonnet-4-20250514", defaults: def)
        case .openai:
            return Provider(name: n, kind: .openai,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o", defaults: def)
        case .custom:
            // Pre-filled with working Azure Responses API example
            return Provider(name: n, kind: .custom,
                baseURL: "https://RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview",
                model: "DEPLOYMENT-NAME",
                defaults: def)
        }
    }

    // MARK: Well-known stable IDs — used for backward-compat migration
    static let claudeAzureID  = "A0000000-0000-0000-0000-000000000001"
    static let claudeDirectID = "A0000000-0000-0000-0000-000000000002"
    static let openaiID       = "A0000000-0000-0000-0000-000000000003"
    static let customID       = "A0000000-0000-0000-0000-000000000004"

    static let legacyMap: [String: String] = [
        "azure_anthropic": claudeAzureID, "anthropic": claudeDirectID,
        "azure_openai": openaiID, "azure_openai_2": openaiID,
        "openai": openaiID, "custom_openai": customID,
    ]
}

// MARK: - ProvidersFile
// Format of {configFolder}/providers.json: {"llm_providers": [...]}

struct ProvidersFile: Codable {
    var llmProviders: [Provider]
    enum CodingKeys: String, CodingKey { case llmProviders = "llm_providers" }
}

// MARK: - AppConfig

struct AppConfig: Codable {
    var schemaVersion: Int
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int
    var actions: [Action]
    var providers: [Provider]
    var configFolderPath: String?
    var sessionFolderPath: String?   // Separate folder for per-day session Markdown files
    var autoCopyAndClose: Bool = false
    var historyLimit: Int = 5
    var modelPresets: [String: [ModelPreset]] = [:]
    var recordSessions: Bool = false
    /// Max chars shown in clipboard preview (0 = unlimited)
    var clipboardPreviewChars: Int = 300

    init(schemaVersion: Int = 1, hotkeyKeyCode: Int, hotkeyModifiers: Int,
         actions: [Action], providers: [Provider] = [],
         configFolderPath: String? = nil, sessionFolderPath: String? = nil,
         autoCopyAndClose: Bool = false,
         historyLimit: Int = 5, modelPresets: [String: [ModelPreset]] = [:],
         recordSessions: Bool = false, clipboardPreviewChars: Int = 300) {
        self.schemaVersion          = schemaVersion
        self.hotkeyKeyCode          = hotkeyKeyCode
        self.hotkeyModifiers        = hotkeyModifiers
        self.actions                = actions
        self.providers              = providers
        self.configFolderPath       = configFolderPath
        self.sessionFolderPath      = sessionFolderPath
        self.autoCopyAndClose       = autoCopyAndClose
        self.historyLimit           = historyLimit
        self.modelPresets           = modelPresets
        self.recordSessions         = recordSessions
        self.clipboardPreviewChars  = clipboardPreviewChars
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion          = try c.decode(Int.self,      forKey: .schemaVersion)
        hotkeyKeyCode          = try c.decode(Int.self,      forKey: .hotkeyKeyCode)
        hotkeyModifiers        = try c.decode(Int.self,      forKey: .hotkeyModifiers)
        actions                = try c.decode([Action].self, forKey: .actions)
        configFolderPath       = try c.decodeIfPresent(String.self,  forKey: .configFolderPath)
        sessionFolderPath      = try c.decodeIfPresent(String.self,  forKey: .sessionFolderPath)
        autoCopyAndClose       = try c.decodeIfPresent(Bool.self,    forKey: .autoCopyAndClose)      ?? false
        historyLimit           = try c.decodeIfPresent(Int.self,     forKey: .historyLimit)          ?? 5
        modelPresets           = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
        recordSessions         = try c.decodeIfPresent(Bool.self,    forKey: .recordSessions)        ?? false
        providers              = try c.decodeIfPresent([Provider].self, forKey: .providers)          ?? []
        clipboardPreviewChars  = try c.decodeIfPresent(Int.self,     forKey: .clipboardPreviewChars) ?? 300
    }

    static var `default`: AppConfig {
        AppConfig(
            schemaVersion: 1,
            hotkeyKeyCode: Int(kVK_Space),
            hotkeyModifiers: Int(cmdKey | shiftKey),
            actions: [
                Action(name: "CZ",  systemPrompt: "Jsi editor textu. Tvůj jediný úkol: oprav gramatiku, nebo přelož vstupní text do češtiny. Pravidla bez výjimky: (1) Zachovej původní význam, styl a tón beze změny – formální zůstane formální, neformální neformální, ironický ironický, vulgární vulgární. (2) Neupravuj strukturu vět více než je gramaticky nutné. (3) Výstup obsahuje POUZE výsledný text. Žádný komentář, žádné vysvětlení, žádný úvod, žádný závěr, žádná otázka, žádné emoji, žádný markdown.", provider: "", model: "", enabled: true),
                Action(name: "EN",  systemPrompt: "You are a text editor. Your only task: correct grammar, or translate the input text into English. Rules without exception: (1) Preserve the original meaning, style and tone exactly – formal stays formal, casual stays casual, ironic stays ironic, vulgar stays vulgar. (2) Do not restructure sentences beyond what is grammatically necessary. (3) Output contains ONLY the resulting text. No commentary, no explanation, no introduction, no conclusion, no questions, no emoji, no markdown.", provider: "", model: "", enabled: true),
                Action(name: "ASK", systemPrompt: "Jsi faktografická databáze. Tvůj jediný úkol: odpověz na položený dotaz. Pravidla bez výjimky: (1) Odpověď musí být stručná, faktická a neutrální. (2) Žádné názory, hodnocení, emoce, doporučení ani spekulace. (3) Žádné doplňující otázky, žádné nabídky další pomoci, žádné závěrečné věty typu 'Chceš vědět více?'. (4) Žádné emoji, žádný markdown, žádné tučné písmo. (5) Pokud existuje více pohledů, uveď je vyváženě v jednom odstavci. (6) Pokud odpověď neznáš, napiš pouze: NULL.", provider: "", model: "", enabled: true),
                Action(name: "KEY", systemPrompt: "Jsi extraktor informací. Tvůj jediný úkol: extrahuj klíčové informace ze vstupního textu nebo obrázku. Pravidla bez výjimky: (1) Na první řádek napiš krátké shrnutí (1 věta) o čem obsah je, ve formátu: Shrnutí: <text>. (2) Každou další klíčovou informaci (fakta, čísla, hodnoty, data, názvy, URL adresy, závěry) napiš na samostatný řádek. (3) Žádný markdown, žádné odrážky, žádné hvězdičky, žádné tučné písmo, žádný komentář, žádný úvod, žádné emoji, žádné otázky. (4) Zachovej čísla a hodnoty přesně tak, jak jsou v originále.", provider: "", model: "", enabled: true),
                Action(name: "WEB", systemPrompt: "Jsi webový čtenář. Tvůj jediný úkol: zpracuj URL nebo doménové jméno ze vstupu (i bez http, např. csfd.cz) a vytvoř shrnutí stránky v češtině. Pravidla bez výjimky: (1) Výstup obsahuje POUZE shrnutí – o čem stránka je, klíčové informace, data, fakta. (2) Žádný markdown, žádné tučné písmo, žádné hvězdičky, žádné emoji, žádné otázky, žádné nabídky další pomoci. (3) Pokud stránka není dostupná, napiš pouze: URL přístup selhal. (4) Pokud vstup neobsahuje žádnou URL ani doménové jméno, napiš pouze: Žádná URL adresa nenalezena.", provider: "", model: "", enabled: true),
            ],
            providers: []
        )
    }
}

// MARK: - Action

struct Action: Codable, Identifiable, Hashable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var provider: String        // UUID string (references Provider.id); legacy: ProviderType rawValue
    var model: String
    var enabled: Bool
    var temperature: Double
    var maxTokens: Int
    var autoCopyClose: AutoCopyClose

    init(name: String, systemPrompt: String, provider: String, model: String, enabled: Bool,
         temperature: Double = 0.7, maxTokens: Int = 4096, autoCopyClose: AutoCopyClose = .useGlobal) {
        self.id           = UUID()
        self.name         = name
        self.systemPrompt = systemPrompt
        self.provider     = provider
        self.model        = model
        self.enabled      = enabled
        self.temperature  = temperature
        self.maxTokens    = maxTokens
        self.autoCopyClose = autoCopyClose
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = (try? c.decode(UUID.self,   forKey: .id)) ?? UUID()
        name          = try  c.decode(String.self,  forKey: .name)
        systemPrompt  = try  c.decode(String.self,  forKey: .systemPrompt)
        model         = try  c.decode(String.self,  forKey: .model)
        enabled       = try  c.decode(Bool.self,    forKey: .enabled)
        temperature   = try  c.decodeIfPresent(Double.self,        forKey: .temperature)   ?? 0.7
        maxTokens     = try  c.decodeIfPresent(Int.self,           forKey: .maxTokens)     ?? 4096
        autoCopyClose = try  c.decodeIfPresent(AutoCopyClose.self, forKey: .autoCopyClose) ?? .useGlobal

        // provider: use string as-is; map legacy ProviderType rawValues to well-known IDs
        let providerStr = try c.decode(String.self, forKey: .provider)
        provider = Provider.legacyMap[providerStr] ?? providerStr
    }
}

// MARK: - AutoCopyClose

enum AutoCopyClose: String, Codable, CaseIterable {
    case useGlobal, always, never
    var displayName: String {
        switch self {
        case .useGlobal: "Dle nastavení"
        case .always:    "Vždy"
        case .never:     "Nikdy"
        }
    }
}
