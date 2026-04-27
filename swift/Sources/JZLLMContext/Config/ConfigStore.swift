import Carbon
import Foundation

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    // Main config file: ~/Library/Application Support/JZLLMContext/config.json
    // Stores: hotkey, preferences, modelPresets, configFolderPath.
    // When configFolderPath is set, agents and providers are loaded from / saved
    // to {configFolderPath}/agents.json and {configFolderPath}/providers.json.
    private let fileURL: URL
    private(set) var config: AppConfig

    var hotkeyKeyCode: Int  { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action]   { config.actions }

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

    /// Write agents.json and providers.json to the config folder (if set).
    private func syncFolder() {
        guard let folderPath = config.configFolderPath, !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // agents.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config.actions) {
            try? data.write(to: folder.appendingPathComponent("agents.json"), options: .atomic)
        }

        // providers.json
        if let data = try? encoder.encode(config.toProvidersConfig()) {
            try? data.write(to: folder.appendingPathComponent("providers.json"), options: .atomic)
        }

        // Ensure session/ subfolder exists
        let sessionDir = folder.appendingPathComponent("session", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    }

    // MARK: - Load helpers

    private static func loadMain(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Overlay actions and providers from the folder when configFolderPath is set.
    private static func overlayFromFolder(_ config: inout AppConfig) {
        guard let folderPath = config.configFolderPath, !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)

        let agentsURL    = folder.appendingPathComponent("agents.json")
        let providersURL = folder.appendingPathComponent("providers.json")

        if let data = try? Data(contentsOf: agentsURL),
           let actions = try? JSONDecoder().decode([Action].self, from: data) {
            config.actions = actions
        }

        if let data = try? Data(contentsOf: providersURL),
           let pc = try? JSONDecoder().decode(ProvidersConfig.self, from: data) {
            config.applyProviders(pc)
        }
    }
}
