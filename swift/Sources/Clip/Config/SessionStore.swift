import Foundation

// MARK: - SessionStore

/// Appends completed operations to per-day Markdown files.
///
/// Priority for the session directory:
///   1. AppConfig.sessionFolderPath  (dedicated sessions folder — e.g. Obsidian vault)
///   2. AppConfig.configFolderPath + "/sessions/"
///   3. nil  → recording disabled (no folder configured)
///
/// File naming: YYYY-MM-DD.md  — one file per calendar day.
/// Each operation is appended as a level-2 section.
final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore()
    private init() {}

    // MARK: - Write

    @discardableResult
    func save(agent: String, provider: String, model: String,
              input: String, output: String, duration: Double) -> URL? {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let dir = sessionDirectory() else { return nil }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(dayFilename())

            let now = Date()
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "HH:mm"
            timeFmt.locale = Locale(identifier: "en_US_POSIX")

            let durationStr = String(format: "%.1fs", duration)
            let modelLabel  = model.isEmpty ? provider : "\(model) · \(provider)"
            let cleanInput  = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

            let section = """
            ## \(timeFmt.string(from: now)) — \(agent) [\(durationStr)] · \(modelLabel)

            **Vstup:**
            \(cleanInput)

            **Výstup:**
            \(cleanOutput)

            ---

            """

            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: fileURL),
                      let data = section.data(using: .utf8) else { return nil }
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                let dayFmt = DateFormatter()
                dayFmt.dateFormat = "yyyy-MM-dd"
                dayFmt.locale = Locale(identifier: "en_US_POSIX")
                let header = "# \(dayFmt.string(from: now))\n\n"
                try (header + section).data(using: .utf8)?.write(to: fileURL)
            }
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Directory

    /// Returns the session directory URL, or nil when no session folder is configured.
    func sessionDirectory() -> URL? {
        let cfg = ConfigStore.shared.config
        if let p = cfg.sessionFolderPath, !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        if let p = cfg.configFolderPath, !p.isEmpty {
            return URL(fileURLWithPath: p).appendingPathComponent("sessions", isDirectory: true)
        }
        return nil
    }

    // MARK: - Helpers

    private func dayFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return "\(fmt.string(from: Date())).md"
    }
}
