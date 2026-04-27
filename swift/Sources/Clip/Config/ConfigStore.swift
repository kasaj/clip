import Carbon
import Foundation

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    // Main config: ~/Library/Application Support/Clip/config.json
    // When configFolderPath is set, agents and providers (incl. API keys) are
    // loaded from / saved to {configFolderPath}/agents.json and providers.json.
    private let fileURL: URL
    private(set) var config: AppConfig

    var hotkeyKeyCode: Int  { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action]   { config.actions }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Clip", isDirectory: true)
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

    func reloadFromFolder() {
        ConfigStore.overlayFromFolder(&config)
    }

    // MARK: - Folder sync

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

        // providers.json — only write when there are providers to avoid overwriting with empty
        if !config.providers.isEmpty {
            let exports = config.providers.map { provider in
                ProviderExport(
                    from: provider,
                    apiKey: try? KeychainStore.load(forProviderID: provider.id)
                )
            }
            if let data = try? encoder.encode(exports) {
                try? data.write(to: folder.appendingPathComponent("providers.json"), options: .atomic)
            }
        }
    }

    // MARK: - Load helpers

    private static func loadMain(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    private static func overlayFromFolder(_ config: inout AppConfig) {
        guard let folderPath = config.configFolderPath, !folderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: folderPath)

        // agents.json
        if let data = try? Data(contentsOf: folder.appendingPathComponent("agents.json")),
           let actions = try? JSONDecoder().decode([Action].self, from: data) {
            config.actions = actions
        }

        // providers.json — [ProviderExport] array; only override when non-empty
        if let data = try? Data(contentsOf: folder.appendingPathComponent("providers.json")),
           let exports = try? JSONDecoder().decode([ProviderExport].self, from: data),
           !exports.isEmpty {
            config.providers = exports.map(\.asProvider)
            // Push API keys into Keychain
            for export in exports {
                if let key = export.apiKey, !key.isEmpty {
                    try? KeychainStore.save(apiKey: key, forProviderID: export.id)
                }
            }
        }
    }
}
