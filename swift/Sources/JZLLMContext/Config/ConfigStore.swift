import Carbon
import Foundation

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    // Main config file: ~/Library/Application Support/JZLLMContext/config.json
    // Stores: hotkey, preferences, modelPresets, configFolderPath.
    // When configFolderPath is set, agents and providers (incl. API keys) are
    // loaded from / saved to {configFolderPath}/agents.json and providers.json.
    private let fileURL: URL
    private(set) var config: AppConfig

    var hotkeyKeyCode: Int   { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action]    { config.actions }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JZLLMContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        var loaded = (try? ConfigStore.loadMain(from: fileURL)) ?? AppConfig.default
        ConfigStore.overlayFromFolder(&loaded)
        config = loaded
    }

    // MARK: - Public API

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        try? save()
        syncFolder()
    }

    /// Call after changing configFolderPath so agents + providers are re-read.
    func reloadFromFolder() {
        ConfigStore.overlayFromFolder(&config)
    }

    // MARK: - Folder sync

    /// Write agents.json and providers.json (incl. API keys from Keychain) to the config folder.
    private func syncFolder() {
        guard let folderPath = config.configFolderPath, !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // agents.json
        if let data = try? encoder.encode(config.actions) {
            try? data.write(to: folder.appendingPathComponent("agents.json"), options: .atomic)
        }

        // providers.json — endpoints + API keys read from Keychain
        var pc = config.toProvidersConfig()
        pc.keyAzureAnthropic = try? KeychainStore.load(for: .azureAnthropic)
        pc.keyAnthropic      = try? KeychainStore.load(for: .anthropic)
        pc.keyAzureOpenai    = try? KeychainStore.load(for: .azureOpenai)
        pc.keyAzureOpenai2   = try? KeychainStore.load(for: .azureOpenai2)
        pc.keyOpenai         = try? KeychainStore.load(for: .openai)
        pc.keyCustomOpenAI   = try? KeychainStore.load(for: .customOpenAI)
        if let data = try? encoder.encode(pc) {
            try? data.write(to: folder.appendingPathComponent("providers.json"), options: .atomic)
        }

        // session/ subfolder
        let sessionDir = folder.appendingPathComponent("session", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    }

    // MARK: - Load helpers

    private static func loadMain(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Overlay actions, endpoints and API keys from the config folder.
    private static func overlayFromFolder(_ config: inout AppConfig) {
        guard let folderPath = config.configFolderPath, !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)

        // agents.json
        if let data = try? Data(contentsOf: folder.appendingPathComponent("agents.json")),
           let actions = try? JSONDecoder().decode([Action].self, from: data) {
            config.actions = actions
        }

        // providers.json — apply endpoints and push API keys into Keychain
        if let data = try? Data(contentsOf: folder.appendingPathComponent("providers.json")),
           let pc = try? JSONDecoder().decode(ProvidersConfig.self, from: data) {
            config.applyProviders(pc)
            // Sync keys from file → Keychain (only if non-empty)
            let keyMap: [(String?, ProviderType)] = [
                (pc.keyAzureAnthropic, .azureAnthropic),
                (pc.keyAnthropic,      .anthropic),
                (pc.keyAzureOpenai,    .azureOpenai),
                (pc.keyAzureOpenai2,   .azureOpenai2),
                (pc.keyOpenai,         .openai),
                (pc.keyCustomOpenAI,   .customOpenAI)
            ]
            for (key, provider) in keyMap {
                if let key, !key.isEmpty {
                    try? KeychainStore.save(apiKey: key, for: provider)
                }
            }
        }
    }
}
