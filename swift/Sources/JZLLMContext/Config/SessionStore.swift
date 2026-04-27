import Foundation

// MARK: - SessionEntry

/// One recorded operation: agent, input, output, timing.
/// Serialised as {timestamp}_{agent}.json inside the session/ folder.
struct SessionEntry: Codable {
    let timestamp: Date
    let agent: String
    let provider: String
    let model: String
    let input: String
    let output: String
    let durationSeconds: Double
}

// MARK: - SessionStore

/// Persists completed operations to disk when recording is enabled.
///
/// Storage location (in priority order):
///  1. {configFolderPath}/session/   — when a config folder is set
///  2. ~/Library/Application Support/Clip/session/  — local fallback
///
/// Recording is active only when `AppConfig.recordSessions == true`.
final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore()
    private init() {}

    // MARK: - Public API

    func save(agent: String, provider: String, model: String,
              input: String, output: String, duration: Double) {
        guard ConfigStore.shared.config.recordSessions else { return }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let entry = SessionEntry(
            timestamp: Date(),
            agent: agent,
            provider: provider,
            model: model,
            input: input,
            output: output,
            durationSeconds: duration
        )

        let dir = sessionDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            let filename = makeFilename(date: entry.timestamp, agent: agent)
            let fileURL = dir.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal — session recording is best-effort
        }
    }

    // MARK: - Helpers

    private func sessionDirectory() -> URL {
        let config = ConfigStore.shared.config
        if let folderPath = config.configFolderPath, !folderPath.isEmpty {
            return URL(fileURLWithPath: folderPath).appendingPathComponent("session", isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Clip/session", isDirectory: true)
    }

    private func makeFilename(date: Date, agent: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let safe = agent.components(separatedBy: .alphanumerics.inverted).joined()
        let ts = fmt.string(from: date)
        return "\(ts)_\(safe).json"
    }
}
