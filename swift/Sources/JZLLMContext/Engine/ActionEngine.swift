import Foundation

@MainActor
final class ActionEngine: ObservableObject {
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastError: Error?
    /// Non-nil while the engine is fetching a web page before sending to the LLM.
    @Published var fetchStatus: String?

    private var currentTask: Task<Void, Never>?

    func run(action: Action, input: String) {
        cancel()
        isLoading = true
        errorMessage = nil
        result = ""
        fetchStatus = nil

        currentTask = Task {
            defer {
                isLoading = false
                fetchStatus = nil
            }

            // ── URL pre-fetch (mirrors python/fetch.py logic) ──────────────
            var effectiveInput = input
            let rawText = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if WebFetcher.isURL(rawText) {
                fetchStatus = "Načítám stránku…"
                do {
                    let pageText = try await WebFetcher.fetch(rawText)
                    effectiveInput = "URL: \(rawText)\n\nObsah stránky:\n\(pageText)"
                } catch {
                    // Fetch failed — tell the LLM so it can handle gracefully
                    effectiveInput = "URL: \(rawText)\n\n[Obsah stránky se nepodařilo načíst: \(error.localizedDescription)]"
                }
                fetchStatus = nil
            }

            // ── LLM streaming ─────────────────────────────────────────────
            let started = Date()
            do {
                let provider = try ProviderFactory.make(for: action)
                for try await chunk in provider.stream(
                    systemPrompt: action.systemPrompt, userContent: effectiveInput
                ) {
                    result += chunk
                }
                // Record session after successful completion
                let duration = Date().timeIntervalSince(started)
                let captured = result
                SessionStore.shared.save(
                    agent:    action.name,
                    provider: action.provider.rawValue,
                    model:    action.model,
                    input:    effectiveInput,
                    output:   captured,
                    duration: duration
                )
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
    }

    func showText(_ text: String) {
        cancel()
        result = text
        errorMessage = nil
    }
}
