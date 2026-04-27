import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var engine = ActionEngine()
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var speech = SpeechPlayer.shared

    // Context
    @State private var contextText: String?
    @State private var contextError: String?
    @State private var isResolvingContext = false
    @State private var contextIsFromOCR = false
    @State private var showFullContext = false
    @State private var useSelectedText = false       // clipboard vs selected text

    // Operation options
    @State private var recordThisSession = false     // per-op session recording
    @State private var readOutput = false            // text-to-speech after completion

    // Supplementary context
    @State private var userContext: String = ""
    @FocusState private var userContextFocused: Bool

    // History panel
    @State private var showHistory = false
    @State private var shownHistoryResult: String?

    // Inline action editing
    @State private var editingAction: Action?

    // Result
    @State private var lastAction: Action?
    @State private var didCopy = false

    private var actions: [Action] { ConfigStore.shared.actions.filter(\.enabled) }
    private var hasConfigFolder: Bool {
        !(ConfigStore.shared.config.configFolderPath ?? "").isEmpty
    }
    private var hasSelectedText: Bool { state.capturedSelectedText != nil }
    private var displayedResult: String? {
        shownHistoryResult ?? (engine.result.isEmpty ? nil : engine.result)
    }
    private var isMissingKeyError: Bool {
        guard let err = engine.lastError as? LLMError, case .missingAPIKey = err else { return false }
        return true
    }
    private var hasResult: Bool { displayedResult != nil || engine.errorMessage != nil }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if showHistory { historyPanel; Divider() }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    contextPreview
                    userContextField
                    optionCheckboxes
                    actionButtons
                }
                .padding(16)
            }
            .frame(maxHeight: hasResult ? 200 : .infinity)
            if hasResult {
                Divider()
                resultArea.padding(16)
            }
        }
        .frame(minWidth: 480, idealWidth: 640, maxWidth: .infinity,
               minHeight: 300, idealHeight: 480, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear { resolveContext() }
        .onChange(of: state.refreshID) { resolveContext() }
        .onChange(of: engine.isLoading) { _, loading in
            guard !loading, engine.errorMessage == nil, !engine.result.isEmpty else { return }
            let sessionURL = engine.lastSessionURL
            HistoryStore.shared.add(actionName: lastAction?.name ?? "",
                                    input: currentContextText,
                                    result: engine.result,
                                    sessionFileURL: sessionURL)
            // Text-to-speech
            if readOutput { SpeechPlayer.shared.speak(engine.result) }

            let shouldCopyClose: Bool
            switch lastAction?.autoCopyClose {
            case .always:  shouldCopyClose = true
            case .never:   shouldCopyClose = false
            default:       shouldCopyClose = ConfigStore.shared.config.autoCopyAndClose
            }
            if shouldCopyClose { copyResult(); onClose() }
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress { press in
            guard !userContextFocused,
                  let digit = Int(press.characters),
                  digit >= 1, digit <= actions.count else { return .ignored }
            runAction(actions[digit - 1])
            return .handled
        }
        .sheet(item: $editingAction) { action in
            ActionEditSheet(action: action) {
                editingAction = nil
                ConfigStore.shared.update { $0.actions = ConfigStore.shared.config.actions }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Clip")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if ConfigStore.shared.config.historyLimit > 0 {
                Button { showHistory.toggle() } label: {
                    Image(systemName: showHistory ? "clock.fill" : "clock")
                        .foregroundStyle(showHistory ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - History panel

    private var historyPanel: some View {
        Group {
            if history.entries.isEmpty {
                Text("Žádná historie").font(.caption).foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.entries) { entry in
                            HStack(alignment: .top) {
                                Button {
                                    shownHistoryResult = entry.result
                                    showHistory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(entry.actionName).font(.caption).fontWeight(.medium)
                                            Spacer()
                                            Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        Text(entry.inputSnippet).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                // Open session file if recorded
                                if let url = entry.sessionFileURL {
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    } label: {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Otevřít záznam v Finderu")
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Feature 1: Clipboard preview (masked) + source toggle

    private var contextPreview: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: contextIsFromOCR ? "doc.viewfinder" : (useSelectedText ? "text.cursor" : "doc.on.clipboard"))
                    .foregroundStyle(.secondary).font(.caption).padding(.top, 1)
                Group {
                    if isResolvingContext {
                        Text(contextIsFromOCR ? "Rozpoznávám text…" : "Čtu kontext…")
                            .foregroundStyle(.secondary)
                    } else if let text = contextText {
                        Text(maskedPreview(text)).lineLimit(showFullContext ? 6 : 2)
                    } else {
                        Text("Žádný obsah").foregroundStyle(.secondary)
                    }
                }
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)

                if contextText != nil && !isResolvingContext {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { showFullContext.toggle() } } label: {
                        Image(systemName: showFullContext ? "eye.slash" : "eye")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help(showFullContext ? "Skrýt obsah" : "Zobrazit obsah")
                }
            }

            // Source toggle: clipboard / selected text
            if hasSelectedText {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle(isOn: $useSelectedText) {
                        Text(useSelectedText ? "Vybraný text" : "Schránka")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: useSelectedText) { resolveContext() }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func maskedPreview(_ text: String) -> String {
        if showFullContext {
            return text.count > 400 ? String(text.prefix(400)) + "…" : text
        }
        let prefix = String(text.prefix(3))
        let bullets = String(repeating: "•", count: min(max(text.count - 3, 0), 24))
        return prefix + bullets
    }

    // MARK: - Supplementary context

    private var userContextField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble").foregroundStyle(.secondary).font(.caption).padding(.top, 2)
            TextField("Doplňkový kontext…", text: $userContext, axis: .vertical)
                .focused($userContextFocused).font(.caption).lineLimit(1...3).frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Option checkboxes

    @ViewBuilder
    private var optionCheckboxes: some View {
        HStack(spacing: 16) {
            // Session recording (only when folder configured)
            if hasConfigFolder {
                Toggle(isOn: $recordThisSession) {
                    Label("Zaznamenat", systemImage: "square.and.arrow.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Uložit vstup a výstup do session logu")
            }

            // Read output aloud
            Toggle(isOn: $readOutput) {
                Label("Přečíst výstup", systemImage: "speaker.wave.2")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Přečíst výsledek nahlas (text-to-speech)")
            if speech.isSpeaking {
                Button("Stop") { speech.stop() }
                    .font(.caption2).buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            // URL hint
            if let text = contextText,
               WebFetcher.isURL(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.caption2).foregroundStyle(.blue)
                    Text("URL — obsah stránky se načte automaticky").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
            }
            if let status = engine.fetchStatus {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
            }

            if contextIsFromOCR {
                actionButton(title: "Rozpoznat text z obrázku (OCR)", missingKey: false, isRunning: false, keyHint: nil) {
                    if let text = contextText { engine.showText(text) }
                }
                Divider()
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: 6) {
                    actionButton(
                        title: action.name,
                        missingKey: !hasKey(for: action),
                        isRunning: engine.isLoading && lastAction == action,
                        keyHint: index < 9 ? String(index + 1) : nil
                    ) { runAction(action) }
                    // Inline edit button
                    Button {
                        var a = action; editingAction = a
                    } label: {
                        Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Upravit akci \(action.name)")
                    .disabled(engine.isLoading)
                }
            }
            if engine.isLoading {
                HStack { Spacer(); Button("Zrušit") { engine.cancel() }.buttonStyle(.bordered) }
            }
        }
    }

    private func actionButton(title: String, missingKey: Bool, isRunning: Bool,
                              keyHint: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if isRunning { ProgressView().scaleEffect(0.65) }
                else if missingKey { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption) }
                else if let hint = keyHint { Text(hint).font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
                else { Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.caption) }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .disabled(engine.isLoading || contextText == nil)
    }

    // MARK: - Result area

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = engine.errorMessage, shownHistoryResult == nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let action = lastAction { Button("Zkusit znovu") { runAction(action) } }
                    if isMissingKeyError { Button("Otevřít nastavení") { onOpenSettings() } }
                }
                Spacer()
            } else if let result = displayedResult {
                ScrollView {
                    Text(result).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button(didCopy ? "Zkopírováno ✓" : "Zkopírovat") { copyResult() }
                        .keyboardShortcut("c", modifiers: .command)
                    Spacer()
                    Button("Zavřít") { onClose() }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentContextText: String { contextText ?? "" }

    private func hasKey(for action: Action) -> Bool {
        guard let uuid = UUID(uuidString: action.provider) else { return false }
        return KeychainStore.hasKey(forProviderID: uuid)
    }

    private func resolveVariables(in prompt: String) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .none; df.locale = Locale.current
        let lang = Locale.current.language.languageCode?.identifier ?? "cs"
        return prompt
            .replacingOccurrences(of: "{{datum}}", with: df.string(from: Date()))
            .replacingOccurrences(of: "{{jazyk}}", with: lang)
            .replacingOccurrences(of: "{{kontext}}", with: userContext)
    }

    private func resolveContext() {
        userContextFocused = false
        engine.reset()
        speech.stop()
        isResolvingContext = true
        contextText = nil
        contextError = nil
        didCopy = false
        shownHistoryResult = nil
        showHistory = false
        showFullContext = false
        recordThisSession = false

        // If selected text is available and toggle is on, use it directly
        if useSelectedText, let sel = state.capturedSelectedText, !sel.isEmpty {
            contextText = sel
            contextIsFromOCR = false
            isResolvingContext = false
            return
        }

        // Otherwise: clipboard / OCR
        let pb = NSPasteboard.general
        contextIsFromOCR = pb.string(forType: .string)?.isEmpty != false && NSImage(pasteboard: pb) != nil
        Task {
            let result = await ContextResolver.resolve()
            switch result {
            case .text(let text, let isOCR): contextText = text; contextIsFromOCR = isOCR
            case .error(let error): contextError = error.localizedDescription
            }
            isResolvingContext = false
        }
    }

    private func runAction(_ action: Action) {
        guard let text = contextText else { return }
        userContextFocused = false
        lastAction = action
        didCopy = false
        shownHistoryResult = nil
        var resolved = action
        resolved.systemPrompt = resolveVariables(in: action.systemPrompt)
        let input: String
        if !userContext.isEmpty && !action.systemPrompt.contains("{{kontext}}") {
            input = text + "\n\n---\nDoplňkový kontext: " + userContext
        } else {
            input = text
        }
        engine.run(action: resolved, input: input, recordSession: recordThisSession)
    }

    private func copyResult() {
        guard let text = displayedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
    }
}

// MARK: - Action Edit Sheet

struct ActionEditSheet: View {
    @State private var action: Action
    let onDone: () -> Void

    init(action: Action, onDone: @escaping () -> Void) {
        self._action = State(initialValue: action)
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Upravit agenta").font(.headline); Spacer() }.padding()
            Divider()
            ScrollView {
                ActionRow(action: $action)
                    .padding()
                    .onChange(of: action) {
                        ConfigStore.shared.update { store in
                            if let idx = store.actions.firstIndex(where: { $0.id == action.id }) {
                                store.actions[idx] = action
                            }
                        }
                    }
            }
            Divider()
            HStack { Spacer(); Button("Hotovo") { onDone() }.buttonStyle(.borderedProminent) }.padding()
        }
        .frame(width: 560, height: 440)
    }
}
