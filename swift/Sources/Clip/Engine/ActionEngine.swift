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

    func run(action: Action, input: String, recordSession: Bool = false,
             loadURL: Bool = false, imageData: Data? = nil, imageMimeType: String? = nil) {
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

            if loadURL {
                if WebFetcher.isURL(rawText) {
                    // Entire input is a single URL — replace with page content
                    fetchStatus = "Loading page…"
                    do {
                        let pageText = try await WebFetcher.fetch(rawText)
                        effectiveInput = "URL: \(rawText)\n\nPage content:\n\(pageText)"
                    } catch {
                        effectiveInput = "URL: \(rawText)\n\n[Could not load page: \(error.localizedDescription)]"
                    }
                    fetchStatus = nil
                } else {
                    // Text containing one or more URLs — fetch each and append
                    let urls = WebFetcher.extractURLs(from: rawText)
                    if !urls.isEmpty {
                        fetchStatus = urls.count == 1 ? "Loading page…" : "Loading \(urls.count) pages…"
                        var appended = rawText
                        for url in urls {
                            do {
                                let pageText = try await WebFetcher.fetch(url)
                                appended += "\n\n---\nContent from \(url):\n\(pageText)"
                            } catch {
                                appended += "\n\n---\n\(url): [Could not load: \(error.localizedDescription)]"
                            }
                        }
                        effectiveInput = appended
                        fetchStatus = nil
                    }
                }
            }

            // ── LLM streaming ─────────────────────────────────────────────
            let started = Date()
            do {
                let provider = try ProviderFactory.make(for: action)
                for try await chunk in provider.stream(systemPrompt: action.systemPrompt,
                                                       userContent: effectiveInput,
                                                       imageData: imageData,
                                                       mimeType: imageMimeType) {
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
