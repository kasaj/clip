import Foundation

struct HistoryEntry: Identifiable {
    let id = UUID()
    let actionName: String
    let inputSnippet: String
    let result: String
    let date: Date
    let sessionFileURL: URL?    // Non-nil when this operation was recorded to disk
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var selectedResult: String? = nil
    private init() {}

    func selectResult(_ result: String) { selectedResult = result }
    func clearSelection() { selectedResult = nil }

    func add(actionName: String, input: String, result: String, sessionFileURL: URL? = nil) {
        let limit = ConfigStore.shared.config.historyLimit
        guard limit > 0 else { return }
        entries.insert(
            HistoryEntry(actionName: actionName, inputSnippet: String(input.prefix(80)),
                         result: result, date: Date(), sessionFileURL: sessionFileURL),
            at: 0
        )
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
    }

    func trim(to limit: Int) {
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
    }
}
