import Foundation

// MARK: - SessionListItem

struct SessionListItem: Identifiable {
    let id: URL
    let filename: String
    let entry: SessionEntry
}

// MARK: - SessionEntry

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

/// Persists completed operations to disk.
///
/// Storage: {configFolderPath}/session/  (or App Support/Clip/session/ if no folder).
///
/// Call save() when you want to record an operation. Returns the file URL on success.
final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore()
    private init() {}

    // MARK: - Write

    @discardableResult
    func save(agent: String, provider: String, model: String,
              input: String, output: String, duration: Double) -> URL? {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let entry = SessionEntry(timestamp: Date(), agent: agent, provider: provider, model: model,
                                 input: input, output: output, durationSeconds: duration)
        let dir = sessionDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            let fileURL = dir.appendingPathComponent(makeFilename(date: entry.timestamp, agent: agent))
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Read

    func recentSessions(limit: Int = 15) -> [SessionListItem] {
        let dir = sessionDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionListItem? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(SessionEntry.self, from: data)
                else { return nil }
                return SessionListItem(id: url, filename: url.lastPathComponent, entry: entry)
            }
            .sorted { $0.entry.timestamp > $1.entry.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    func sessionDirectory() -> URL {
        let cfg = ConfigStore.shared.config
        if let p = cfg.configFolderPath, !p.isEmpty {
            return URL(fileURLWithPath: p).appendingPathComponent("session", isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Clip/session", isDirectory: true)
    }

    private func makeFilename(date: Date, agent: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let safe = agent.components(separatedBy: .alphanumerics.inverted).joined()
        return "\(fmt.string(from: date))_\(safe).json"
    }
}
