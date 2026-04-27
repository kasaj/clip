import Foundation

@MainActor
final class ActionEngine: ObservableObject {
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastError: Error?
    @Published var fetchStatus: String?

    /// URL of the session file saved for the last completed operation (nil if not recorded).
    private(set) var lastSessionURL: URL?

    private var currentTask: Task<Void, Never>?

    func run(action: Action, input: String, recordSession: Bool = false) {
        cancel()
        isLoading = true
        errorMessage = nil
        result = ""
        fetchStatus = nil
        lastSessionURL = nil

        currentTask = Task {
            defer { isLoading = false; fetchStatus = nil }

            // ── URL pre-fetch ─────────────────────────────────────────────
            var effectiveInput = input
            let rawText = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if WebFetcher.isURL(rawText) {
                fetchStatus = "Načítám stránku…"
                do {
                    let pageText = try await WebFetcher.fetch(rawText)
                    effectiveInput = "URL: \(rawText)\n\nObsah stránky:\n\(pageText)"
                } catch {
                    effectiveInput = "URL: \(rawText)\n\n[Obsah stránky se nepodařilo načíst: \(error.localizedDescription)]"
                }
                fetchStatus = nil
            }

            // ── LLM streaming ─────────────────────────────────────────────
            let started = Date()
            do {
                let provider = try ProviderFactory.make(for: action)
                for try await chunk in provider.stream(systemPrompt: action.systemPrompt, userContent: effectiveInput) {
                    result += chunk
                }
                let duration = Date().timeIntervalSince(started)
                let captured = result

                // Record session if requested (per-op checkbox) OR global setting is on
                let shouldRecord = recordSession || ConfigStore.shared.config.recordSessions
                if shouldRecord {
                    let providerName = ConfigStore.shared.config.providers
                        .first(where: { $0.id.uuidString == action.provider })?.name ?? action.provider
                    lastSessionURL = SessionStore.shared.save(
                        agent: action.name, provider: providerName,
                        model: action.model, input: effectiveInput,
                        output: captured, duration: duration
                    )
                }
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                lastError = error
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        fetchStatus = nil
    }

    func reset() {
        cancel()
        result = ""
        errorMessage = nil
        lastError = nil
        fetchStatus = nil
        lastSessionURL = nil
    }

    func showText(_ text: String) {
        cancel()
        result = text
        errorMessage = nil
    }
}
