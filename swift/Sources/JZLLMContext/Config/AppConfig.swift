import Carbon
import Foundation

// MARK: - ModelPreset

struct ModelPreset: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var isRecommended: Bool

    init(id: String, displayName: String, isRecommended: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isRecommended = isRecommended
    }
}

// MARK: - ProvidersConfig
// Stored in {configFolder}/providers.json.
// Contains endpoints AND API keys so the entire provider setup is portable
// via iDrive / OneDrive. Keys are synced to/from Keychain automatically.
// This file is gitignored — it lives only in the user's private sync folder.

struct ProvidersConfig: Codable {
    // Endpoints
    var azureAnthropicEndpoint: String?
    var azureAnthropicAPIVersion: String?
    var azureEndpoint: String?
    var azureDeploymentName: String?
    var azureAPIVersion: String?
    var azureEndpoint2: String?
    var azureDeploymentName2: String?
    var azureAPIVersion2: String?
    var customOpenAIBaseURL: String?

    // API keys (synced to Keychain on load; read from Keychain on save)
    var keyAzureAnthropic: String?
    var keyAnthropic: String?
    var keyAzureOpenai: String?
    var keyAzureOpenai2: String?
    var keyOpenai: String?
    var keyCustomOpenAI: String?
}

// MARK: - AppConfig

struct AppConfig: Codable {
    var schemaVersion: Int
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int
    var actions: [Action]

    /// Path to the shared config folder (iDrive / OneDrive / local).
    /// When set, agents.json and providers.json in that folder are used
    /// instead of the values stored here.
    var configFolderPath: String?

    // Azure AI Foundry – Anthropic API (Claude via Azure)
    var azureAnthropicEndpoint: String?
    var azureAnthropicAPIVersion: String?

    // Azure OpenAI – slot 1
    var azureEndpoint: String?
    var azureDeploymentName: String?
    var azureAPIVersion: String?

    // Azure OpenAI – slot 2
    var azureEndpoint2: String?
    var azureDeploymentName2: String?
    var azureAPIVersion2: String?

    var customOpenAIBaseURL: String?
    var autoCopyAndClose: Bool = false
    var historyLimit: Int = 5
    var modelPresets: [String: [ModelPreset]] = [:]

    static let defaultAzureAPIVersion = "2024-10-21"

    // MARK: Provider overlay helpers

    func toProvidersConfig() -> ProvidersConfig {
        ProvidersConfig(
            azureAnthropicEndpoint:   azureAnthropicEndpoint,
            azureAnthropicAPIVersion: azureAnthropicAPIVersion,
            azureEndpoint:            azureEndpoint,
            azureDeploymentName:      azureDeploymentName,
            azureAPIVersion:          azureAPIVersion,
            azureEndpoint2:           azureEndpoint2,
            azureDeploymentName2:     azureDeploymentName2,
            azureAPIVersion2:         azureAPIVersion2,
            customOpenAIBaseURL:      customOpenAIBaseURL
        )
    }

    mutating func applyProviders(_ pc: ProvidersConfig) {
        azureAnthropicEndpoint   = pc.azureAnthropicEndpoint
        azureAnthropicAPIVersion = pc.azureAnthropicAPIVersion
        azureEndpoint            = pc.azureEndpoint
        azureDeploymentName      = pc.azureDeploymentName
        azureAPIVersion          = pc.azureAPIVersion
        azureEndpoint2           = pc.azureEndpoint2
        azureDeploymentName2     = pc.azureDeploymentName2
        azureAPIVersion2         = pc.azureAPIVersion2
        customOpenAIBaseURL      = pc.customOpenAIBaseURL
    }

    // MARK: Init

    init(schemaVersion: Int, hotkeyKeyCode: Int, hotkeyModifiers: Int, actions: [Action],
         configFolderPath: String? = nil,
         azureAnthropicEndpoint: String? = nil, azureAnthropicAPIVersion: String? = nil,
         azureEndpoint: String? = nil, azureDeploymentName: String? = nil, azureAPIVersion: String? = nil,
         azureEndpoint2: String? = nil, azureDeploymentName2: String? = nil, azureAPIVersion2: String? = nil,
         customOpenAIBaseURL: String? = nil,
         autoCopyAndClose: Bool = false, historyLimit: Int = 5,
         modelPresets: [String: [ModelPreset]] = [:]) {
        self.schemaVersion           = schemaVersion
        self.hotkeyKeyCode           = hotkeyKeyCode
        self.hotkeyModifiers         = hotkeyModifiers
        self.actions                 = actions
        self.configFolderPath        = configFolderPath
        self.azureAnthropicEndpoint  = azureAnthropicEndpoint
        self.azureAnthropicAPIVersion = azureAnthropicAPIVersion
        self.azureEndpoint           = azureEndpoint
        self.azureDeploymentName     = azureDeploymentName
        self.azureAPIVersion         = azureAPIVersion
        self.azureEndpoint2          = azureEndpoint2
        self.azureDeploymentName2    = azureDeploymentName2
        self.azureAPIVersion2        = azureAPIVersion2
        self.customOpenAIBaseURL     = customOpenAIBaseURL
        self.autoCopyAndClose        = autoCopyAndClose
        self.historyLimit            = historyLimit
        self.modelPresets            = modelPresets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion            = try c.decode(Int.self,       forKey: .schemaVersion)
        hotkeyKeyCode            = try c.decode(Int.self,       forKey: .hotkeyKeyCode)
        hotkeyModifiers          = try c.decode(Int.self,       forKey: .hotkeyModifiers)
        actions                  = try c.decode([Action].self,  forKey: .actions)
        configFolderPath         = try c.decodeIfPresent(String.self, forKey: .configFolderPath)
        azureAnthropicEndpoint   = try c.decodeIfPresent(String.self, forKey: .azureAnthropicEndpoint)
        azureAnthropicAPIVersion = try c.decodeIfPresent(String.self, forKey: .azureAnthropicAPIVersion)
        azureEndpoint            = try c.decodeIfPresent(String.self, forKey: .azureEndpoint)
        azureDeploymentName      = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName)
        azureAPIVersion          = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion)
        azureEndpoint2           = try c.decodeIfPresent(String.self, forKey: .azureEndpoint2)
        azureDeploymentName2     = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName2)
        azureAPIVersion2         = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion2)
        customOpenAIBaseURL      = try c.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL)
        autoCopyAndClose = try c.decodeIfPresent(Bool.self,                    forKey: .autoCopyAndClose) ?? false
        historyLimit     = try c.decodeIfPresent(Int.self,                     forKey: .historyLimit) ?? 5
        modelPresets     = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
    }

    // MARK: Default config

    static var `default`: AppConfig {
        AppConfig(
            schemaVersion: 1,
            hotkeyKeyCode: Int(kVK_Space),
            hotkeyModifiers: Int(cmdKey | shiftKey),
            actions: [
                Action(
                    name: "CZ",
                    systemPrompt: "Jsi editor textu. Tvůj jediný úkol: oprav gramatiku, nebo přelož vstupní text do češtiny. Pravidla bez výjimky: (1) Zachovej původní význam, styl a tón beze změny – formální zůstane formální, neformální neformální, ironický ironický, vulgární vulgární. (2) Neupravuj strukturu vět více než je gramaticky nutné. (3) Výstup obsahuje POUZE výsledný text. Žádný komentář, žádné vysvětlení, žádný úvod, žádný závěr, žádná otázka, žádné emoji, žádný markdown.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                ),
                Action(
                    name: "EN",
                    systemPrompt: "You are a text editor. Your only task: correct grammar, or translate the input text into English. Rules without exception: (1) Preserve the original meaning, style and tone exactly – formal stays formal, casual stays casual, ironic stays ironic, vulgar stays vulgar. (2) Do not restructure sentences beyond what is grammatically necessary. (3) Output contains ONLY the resulting text. No commentary, no explanation, no introduction, no conclusion, no questions, no emoji, no markdown.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                ),
                Action(
                    name: "ASK",
                    systemPrompt: "Jsi faktografická databáze. Tvůj jediný úkol: odpověz na položený dotaz. Pravidla bez výjimky: (1) Odpověď musí být stručná, faktická a neutrální. (2) Žádné názory, hodnocení, emoce, doporučení ani spekulace. (3) Žádné doplňující otázky, žádné nabídky další pomoci, žádné závěrečné věty typu 'Chceš vědět více?'. (4) Žádné emoji, žádný markdown, žádné tučné písmo. (5) Pokud existuje více pohledů, uveď je vyváženě v jednom odstavci. (6) Pokud odpověď neznáš, napiš pouze: NULL.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                ),
                Action(
                    name: "KEY",
                    systemPrompt: "Jsi extraktor informací. Tvůj jediný úkol: extrahuj klíčové informace ze vstupního textu nebo obrázku. Pravidla bez výjimky: (1) Na první řádek napiš krátké shrnutí (1 věta) o čem obsah je, ve formátu: Shrnutí: <text>. (2) Každou další klíčovou informaci (fakta, čísla, hodnoty, data, názvy, URL adresy, závěry) napiš na samostatný řádek. (3) Žádný markdown, žádné odrážky, žádné hvězdičky, žádné tučné písmo, žádný komentář, žádný úvod, žádné emoji, žádné otázky. (4) Zachovej čísla a hodnoty přesně tak, jak jsou v originále.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                ),
                Action(
                    name: "WEB",
                    systemPrompt: "Jsi webový čtenář. Tvůj jediný úkol: zpracuj URL nebo doménové jméno ze vstupu (i bez http, např. csfd.cz) a vytvoř shrnutí stránky v češtině. Pravidla bez výjimky: (1) Výstup obsahuje POUZE shrnutí – o čem stránka je, klíčové informace, data, fakta. (2) Žádný markdown, žádné tučné písmo, žádné hvězdičky, žádné emoji, žádné otázky, žádné nabídky další pomoci. (3) Pokud stránka není dostupná, napiš pouze: URL přístup selhal. (4) Pokud vstup neobsahuje žádnou URL ani doménové jméno, napiš pouze: Žádná URL adresa nenalezena.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                ),
                Action(
                    name: "M365",
                    systemPrompt: "Jsi senior M365 service architekt. Odpovídej pouze na základě ověřených informací – preferuj oficiální Microsoft dokumentaci (learn.microsoft.com) a vždy uveď přímý odkaz. Nikdy neodhaduj – pokud si nejsi jistý, řekni to explicitně. Vždy uvažuj v kontextu enterprise prostředí a automaticky zohledni Hybrid scénáře (Hybrid Exchange, Hybrid Entra ID, Hybrid Modern Authentication) pokud je téma relevantní. Délku odpovědi přizpůsob vstupu – krátký dotaz, krátká odpověď; komplexní téma, detailní odpověď. Pokud odpověď vyžaduje aktuální nebo ověřená data, vyhledej je na webu. Pokud je vstupem příkaz nebo cmdlet: uveď účel, syntaxi s klíčovými parametry, příklad v enterprise nebo hybrid kontextu a odkaz na dokumentaci. Pokud je vstupem screenshot nebo obrázek: interpretuj ho jako chybu nebo problém, identifikuj komponentu (Entra ID, Exchange, Security, Defender), navrhni příčiny a řešení, uveď dokumentaci. Nikdy nevymýšlej cmdlety, parametry ani URL – pokud odkaz neznáš s jistotou, řekni to.",
                    provider: .azureAnthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true
                )
            ]
        )
    }
}

// MARK: - Action

struct Action: Codable, Identifiable, Hashable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var provider: ProviderType
    var model: String
    var enabled: Bool
    var temperature: Double
    var maxTokens: Int
    var autoCopyClose: AutoCopyClose

    init(
        name: String,
        systemPrompt: String,
        provider: ProviderType,
        model: String,
        enabled: Bool,
        temperature: Double = 0.7,
        maxTokens: Int = 4096,
        autoCopyClose: AutoCopyClose = .useGlobal
    ) {
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
        id            = (try? c.decode(UUID.self,        forKey: .id)) ?? UUID()
        name          = try  c.decode(String.self,       forKey: .name)
        systemPrompt  = try  c.decode(String.self,       forKey: .systemPrompt)
        provider      = try  c.decode(ProviderType.self, forKey: .provider)
        model         = try  c.decode(String.self,       forKey: .model)
        enabled       = try  c.decode(Bool.self,         forKey: .enabled)
        temperature   = try  c.decodeIfPresent(Double.self,        forKey: .temperature)   ?? 0.7
        maxTokens     = try  c.decodeIfPresent(Int.self,           forKey: .maxTokens)     ?? 4096
        autoCopyClose = try  c.decodeIfPresent(AutoCopyClose.self, forKey: .autoCopyClose) ?? .useGlobal
    }
}

// MARK: - AutoCopyClose

enum AutoCopyClose: String, Codable, CaseIterable {
    case useGlobal
    case always
    case never

    var displayName: String {
        switch self {
        case .useGlobal: "Dle nastavení"
        case .always:    "Vždy"
        case .never:     "Nikdy"
        }
    }
}

// MARK: - ProviderType

enum ProviderType: String, Codable, CaseIterable {
    case azureAnthropic = "azure_anthropic"  // Claude via Azure AI Foundry (Anthropic API)
    case anthropic                            // Claude direct (api.anthropic.com)
    case azureOpenai    = "azure_openai"     // ChatGPT via Azure – slot 1
    case azureOpenai2   = "azure_openai_2"   // ChatGPT via Azure – slot 2
    case openai                              // OpenAI direct (api.openai.com)
    case customOpenAI   = "custom_openai"    // Any OpenAI-compatible endpoint
}
