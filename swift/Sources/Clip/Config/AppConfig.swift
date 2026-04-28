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

enum ProviderKind: String, Codable, CaseIterable {
    case anthropic                    // Anthropic Messages API — direct or Azure AI Foundry
    case openai                       // OpenAI Chat Completions API — direct
    case azureOpenAI = "azure_openai" // Azure OpenAI — builds deployment URL from endpoint.*
    case custom                       // Any OpenAI-compatible endpoint

    var displayName: String {
        switch self {
        case .anthropic:   "Anthropic"
        case .openai:      "OpenAI"
        case .azureOpenAI: "Azure OpenAI"
        case .custom:      "Vlastní (OpenAI-compatible)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic:   "https://api.anthropic.com"
        case .openai:      "https://api.openai.com/v1"
        case .azureOpenAI: ""
        case .custom:      ""
        }
    }

    var presetModels: [ModelPreset] {
        switch self {
        case .anthropic:
            [
                .init(id: "claude-sonnet-4-6",        displayName: "claude-sonnet-4.6", isRecommended: true),
                .init(id: "claude-opus-4-7",           displayName: "claude-opus-4.7"),
                .init(id: "claude-haiku-4-5-20251001", displayName: "claude-haiku-4.5")
            ]
        case .openai:
            [
                .init(id: "gpt-4o",      displayName: "gpt-4o", isRecommended: true),
                .init(id: "gpt-4o-mini", displayName: "gpt-4o-mini"),
                .init(id: "o4-mini",     displayName: "o4-mini"),
                .init(id: "o3",          displayName: "o3"),
                .init(id: "o1",          displayName: "o1"),
            ]
        case .azureOpenAI, .custom:
            []
        }
    }
}

// MARK: - Provider sub-structs (for nested providers.json format)

struct ProviderAuth: Codable, Equatable, Hashable {
    var apiKey: String?
    var authType: String?   // "api_key" | "managed_identity"
    var clientId: String?
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"; case authType = "auth_type"; case clientId = "client_id"
    }
}

struct ProviderEndpoint: Codable, Equatable, Hashable {
    var baseURL: String?          // Full base URL (or root for Azure)
    var apiVersion: String?       // e.g. "2024-02-01"
    var resourceName: String?     // Azure resource name (informational)
    var deploymentName: String?   // Azure deployment name → used to build chat URL
    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"; case apiVersion = "api_version"
        case resourceName = "resource_name"; case deploymentName = "deployment_name"
    }
}

struct ProviderOptions: Codable, Equatable, Hashable {
    var model: String?
    var maxTokens: Int?
    var temperature: Double?
    var timeoutSeconds: Int?
    var organizationId: String?
    enum CodingKeys: String, CodingKey {
        case model; case maxTokens = "max_tokens"; case temperature
        case timeoutSeconds = "timeout_seconds"; case organizationId = "organization_id"
    }
}

// MARK: - Provider

/// A user-managed provider record.
/// API key can live in auth.api_key (providers.json) or Keychain (entered via Settings).
struct Provider: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var enabled: Bool
    var isDefault: Bool
    var auth: ProviderAuth?
    var endpoint: ProviderEndpoint?
    var options: ProviderOptions?

    init(id: UUID = UUID(), name: String, kind: ProviderKind,
         enabled: Bool = true, isDefault: Bool = false,
         auth: ProviderAuth? = nil, endpoint: ProviderEndpoint? = nil,
         options: ProviderOptions? = nil) {
        self.id        = id;    self.name      = name;     self.kind      = kind
        self.enabled   = enabled; self.isDefault = isDefault
        self.auth      = auth;  self.endpoint  = endpoint; self.options   = options
    }

    // Backward-compat decoder: handles both new nested format and old flat format.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled)   ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        auth      = try c.decodeIfPresent(ProviderAuth.self,     forKey: .auth)
        endpoint  = try c.decodeIfPresent(ProviderEndpoint.self, forKey: .endpoint)
        options   = try c.decodeIfPresent(ProviderOptions.self,  forKey: .options)
        // Kind: new JSON uses "provider" key, old JSON uses "kind"
        if let k = try c.decodeIfPresent(ProviderKind.self, forKey: .kind) {
            kind = k
        } else if let k = try c.decodeIfPresent(ProviderKind.self, forKey: .legacyKind) {
            kind = k
        } else { kind = .custom }
        // Legacy flat fields → migrate into nested structs on load
        if endpoint == nil {
            let oldURL = try c.decodeIfPresent(String.self, forKey: .legacyBaseURL)
            let oldVer = try c.decodeIfPresent(String.self, forKey: .legacyApiVersion)
            if oldURL != nil || oldVer != nil {
                endpoint = ProviderEndpoint(
                    baseURL: (oldURL?.isEmpty == false) ? oldURL : nil,
                    apiVersion: oldVer)
            }
        }
        if options == nil {
            if let m = try c.decodeIfPresent(String.self, forKey: .legacyDefaultModel), !m.isEmpty {
                options = ProviderOptions(model: m)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(name,      forKey: .name)
        try c.encode(kind,      forKey: .kind)      // writes "provider" key
        try c.encode(enabled,   forKey: .enabled)
        try c.encode(isDefault, forKey: .isDefault) // writes "default" key
        try c.encodeIfPresent(auth,     forKey: .auth)
        try c.encodeIfPresent(endpoint, forKey: .endpoint)
        try c.encodeIfPresent(options,  forKey: .options)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, auth, endpoint, options
        case kind = "provider"              // new format key
        case isDefault = "default"
        case legacyKind = "kind"            // old format fallback
        case legacyBaseURL = "baseURL"
        case legacyApiVersion = "apiVersion"
        case legacyDefaultModel = "defaultModel"
    }

    // Computed convenience
    var effectiveBaseURL: String    { endpoint?.baseURL ?? kind.defaultBaseURL }
    var effectiveApiVersion: String? { endpoint?.apiVersion }
    var effectiveModel: String      { options?.model ?? "" }

    func effectiveModels(using presets: [String: [ModelPreset]]) -> [ModelPreset] {
        let stored = presets[id.uuidString] ?? []
        return stored.isEmpty ? kind.presetModels : stored
    }

    // MARK: - Template factory — pre-filled config when adding a new provider

    static func template(kind: ProviderKind, name: String = "") -> Provider {
        let n = name.isEmpty ? kind.displayName : name
        switch kind {
        case .anthropic:
            return Provider(name: n, kind: .anthropic,
                auth: ProviderAuth(apiKey: ""),
                endpoint: ProviderEndpoint(baseURL: "https://api.anthropic.com"),
                options: ProviderOptions(model: "claude-sonnet-4-20250514", maxTokens: 4096, temperature: 0.7))
        case .openai:
            return Provider(name: n, kind: .openai,
                auth: ProviderAuth(apiKey: ""),
                endpoint: ProviderEndpoint(baseURL: "https://api.openai.com/v1"),
                options: ProviderOptions(model: "gpt-4o", maxTokens: 4096, temperature: 0.7))
        case .azureOpenAI:
            return Provider(name: n, kind: .azureOpenAI,
                auth: ProviderAuth(apiKey: "", authType: "api_key"),
                endpoint: ProviderEndpoint(baseURL: "https://RESOURCE.openai.azure.com/",
                                           apiVersion: "2024-02-01",
                                           resourceName: "RESOURCE",
                                           deploymentName: "DEPLOYMENT"),
                options: ProviderOptions(model: "gpt-4o", maxTokens: 4096, temperature: 0.7))
        case .custom:
            return Provider(name: n, kind: .custom,
                auth: ProviderAuth(apiKey: ""),
                endpoint: ProviderEndpoint(baseURL: "https://"),
                options: ProviderOptions(model: "", maxTokens: 4096, temperature: 0.7))
        }
    }

    // MARK: Well-known default UUIDs — stable across installs; used for migration
    static let claudeAzureID  = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let claudeDirectID = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    static let openaiID       = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    static let customID       = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!

    static let legacyMap: [String: UUID] = [
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

    init(schemaVersion: Int = 1, hotkeyKeyCode: Int, hotkeyModifiers: Int,
         actions: [Action], providers: [Provider] = [],
         configFolderPath: String? = nil, sessionFolderPath: String? = nil,
         autoCopyAndClose: Bool = false,
         historyLimit: Int = 5, modelPresets: [String: [ModelPreset]] = [:],
         recordSessions: Bool = false) {
        self.schemaVersion    = schemaVersion
        self.hotkeyKeyCode    = hotkeyKeyCode
        self.hotkeyModifiers  = hotkeyModifiers
        self.actions          = actions
        self.providers        = providers
        self.configFolderPath = configFolderPath
        self.sessionFolderPath = sessionFolderPath
        self.autoCopyAndClose = autoCopyAndClose
        self.historyLimit     = historyLimit
        self.modelPresets     = modelPresets
        self.recordSessions   = recordSessions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion     = try c.decode(Int.self,      forKey: .schemaVersion)
        hotkeyKeyCode     = try c.decode(Int.self,      forKey: .hotkeyKeyCode)
        hotkeyModifiers   = try c.decode(Int.self,      forKey: .hotkeyModifiers)
        actions           = try c.decode([Action].self, forKey: .actions)
        configFolderPath  = try c.decodeIfPresent(String.self,  forKey: .configFolderPath)
        sessionFolderPath = try c.decodeIfPresent(String.self,  forKey: .sessionFolderPath)
        autoCopyAndClose  = try c.decodeIfPresent(Bool.self,    forKey: .autoCopyAndClose) ?? false
        historyLimit      = try c.decodeIfPresent(Int.self,     forKey: .historyLimit)     ?? 5
        modelPresets      = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
        recordSessions    = try c.decodeIfPresent(Bool.self,    forKey: .recordSessions)   ?? false
        providers         = try c.decodeIfPresent([Provider].self, forKey: .providers)     ?? []
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
                Action(name: "M365", systemPrompt: "Jsi senior M365 service architekt. Odpovídej pouze na základě ověřených informací – preferuj oficiální Microsoft dokumentaci (learn.microsoft.com) a vždy uveď přímý odkaz. Nikdy neodhaduj – pokud si nejsi jistý, řekni to explicitně. Vždy uvažuj v kontextu enterprise prostředí a automaticky zohledni Hybrid scénáře (Hybrid Exchange, Hybrid Entra ID, Hybrid Modern Authentication) pokud je téma relevantní. Délku odpovědi přizpůsob vstupu – krátký dotaz, krátká odpověď; komplexní téma, detailní odpověď. Pokud odpověď vyžaduje aktuální nebo ověřená data, vyhledej je na webu. Pokud je vstupem příkaz nebo cmdlet: uveď účel, syntaxi s klíčovými parametry, příklad v enterprise nebo hybrid kontextu a odkaz na dokumentaci. Pokud je vstupem screenshot nebo obrázek: interpretuj ho jako chybu nebo problém, identifikuj komponentu (Entra ID, Exchange, Security, Defender), navrhni příčiny a řešení, uveď dokumentaci. Nikdy nevymýšlej cmdlety, parametry ani URL – pokud odkaz neznáš s jistotou, řekni to.", provider: "", model: "", enabled: true),
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

        // provider: try UUID string first, then map legacy ProviderType rawValue
        let providerStr = try c.decode(String.self, forKey: .provider)
        if UUID(uuidString: providerStr) != nil {
            provider = providerStr
        } else {
            // Legacy migration: map ProviderType rawValue → well-known UUID
            provider = (Provider.legacyMap[providerStr] ?? Provider.claudeAzureID).uuidString
        }
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
