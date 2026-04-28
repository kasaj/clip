import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void

    @StateObject private var engine = ActionEngine()
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var speech = SpeechPlayer.shared

    // Context
    @State private var contextText: String?
    @State private var contextImageData: Data?       // set when clipboard has image without text
    @State private var contextMimeType: String = "image/jpeg"
    @State private var isResolvingContext = false
    @State private var contextIsFromOCR = false
    @State private var showFullContext = false
    @State private var ocrSourceImageData: Data?     // original image when OCR found text
    @State private var ocrSourceMimeType: String = "image/jpeg"
    @State private var sendOCRImage = false          // "Also send image" checkbox

    // Prompt / options
    @State private var userPrompt: String = ""
    @FocusState private var promptFocused: Bool
    @State private var ignoreClipboard = false   // skip clipboard; prompt-only mode
    @State private var loadURL = false           // fetch URL(s) found in clipboard
    @State private var loadURLAuto = false       // true when auto-enabled (pure URL)
    @State private var recordThisSession = false
    @State private var readOutput = false

    // History panel
    @State private var showHistory = false
    @State private var shownHistoryResult: String?

    // Inline settings
    @State private var showingSettings = false

    // Inline action editing
    @State private var editingAction: Action?

    // Result
    @State private var lastAction: Action?
    @State private var didCopy = false

    private var actions: [Action] { ConfigStore.shared.actions.filter(\.enabled) }
    private var hasSessionFolder: Bool { SessionStore.shared.sessionDirectory() != nil }
    private var effectiveContext: String? { ignoreClipboard ? nil : contextText }
    private var displayedResult: String? {
        shownHistoryResult ?? (engine.result.isEmpty ? nil : engine.result)
    }
    private var isMissingKeyError: Bool {
        guard let err = engine.lastError as? LLMError, case .missingAPIKey = err else { return false }
        return true
    }
    private var hasResult: Bool { displayedResult != nil || engine.errorMessage != nil }
    private var canRun: Bool {
        !engine.isLoading && (effectiveContext != nil || contextImageData != nil || !userPrompt.isEmpty)
    }

    var body: some View {
        Group {
            if showingSettings {
                settingsWrapper
            } else {
                overlayContent
            }
        }
        .frame(minWidth: 520, idealWidth: 660, maxWidth: .infinity,
               minHeight: 320, idealHeight: 500, maxHeight: .infinity)
        .onAppear {
            recordThisSession = ConfigStore.shared.config.recordSessions
            resolveContext()
        }
        .onChange(of: state.refreshID) {
            recordThisSession = ConfigStore.shared.config.recordSessions
            resolveContext()
        }
        .onChange(of: engine.isLoading) { _, loading in
            guard !loading, engine.errorMessage == nil, !engine.result.isEmpty else { return }
            let sessionURL = engine.lastSessionURL
            HistoryStore.shared.add(actionName: lastAction?.name ?? "",
                                    input: currentInput,
                                    result: engine.result,
                                    sessionFileURL: sessionURL)
            if readOutput { SpeechPlayer.shared.speak(engine.result) }

            let shouldCopyClose: Bool
            switch lastAction?.autoCopyClose {
            case .always:  shouldCopyClose = true
            case .never:   shouldCopyClose = false
            default:       shouldCopyClose = ConfigStore.shared.config.autoCopyAndClose
            }
            if shouldCopyClose { copyResult(); close() }
        }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress { press in
            guard !promptFocused,
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

    // MARK: - Close (stops speech + resets transient state)

    private func close() {
        SpeechPlayer.shared.stop()
        resetTransientState()
        onClose()
    }

    /// Clear per-session inputs so the overlay looks fresh next time.
    /// Record follows the global setting; other checkboxes reset to off.
    private func resetTransientState() {
        userPrompt = ""
        ignoreClipboard = false
        loadURL = false
        loadURLAuto = false
        contextImageData = nil
        ocrSourceImageData = nil
        sendOCRImage = false
        readOutput = false
        recordThisSession = ConfigStore.shared.config.recordSessions
        showHistory = false
        shownHistoryResult = nil
        showingSettings = false
        engine.reset()
    }

    // MARK: - Overlay content

    private var overlayContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if showHistory { historyPanel; Divider() }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    contextPreview
                    promptField
                    optionCheckboxes
                    actionButtons
                }
                .padding(16)
            }
            .frame(maxHeight: hasResult ? 220 : .infinity)
            if hasResult {
                Divider()
                resultArea.padding(16)
            }
        }
    }

    // MARK: - Inline settings wrapper

    private var settingsWrapper: some View {
        VStack(spacing: 0) {
            // Settings header with Back + X
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showingSettings = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.subheadline)
                        Text("Back").font(.subheadline)
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                // Always-visible close button
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            SettingsView()
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
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingSettings = true }
            } label: {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            // Always-visible close button — red so it's easy to spot
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - History panel

    private var historyPanel: some View {
        Group {
            if history.entries.isEmpty {
                Text("No history").font(.caption).foregroundStyle(.secondary).padding(16)
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
                                if let url = entry.sessionFileURL {
                                    Button { NSWorkspace.shared.open(url) } label: {
                                        Image(systemName: "doc.text")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open session log (\(url.lastPathComponent))")
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

    // MARK: - Context preview

    @ViewBuilder
    private var contextPreview: some View {
        if !ignoreClipboard, let imgData = contextImageData,
           let nsImg = NSImage(data: imgData) {
            // Image context — thumbnail + label
            HStack(spacing: 10) {
                Image(nsImage: nsImg)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 80, maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Label("Image in clipboard", systemImage: "photo")
                        .font(.caption).fontWeight(.medium)
                    Text("No text detected — image sent to vision model")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: contextIsFromOCR ? "doc.viewfinder" : "doc.on.clipboard")
                    .foregroundStyle(.secondary).font(.caption).padding(.top, 1)
                Group {
                    if ignoreClipboard {
                        Text("Clipboard ignored — prompt only").foregroundStyle(.secondary)
                    } else if isResolvingContext {
                        Text(contextIsFromOCR ? "Reading image…" : "Reading clipboard…").foregroundStyle(.secondary)
                    } else if let text = contextText {
                        Text(maskedPreview(text)).lineLimit(showFullContext ? 6 : 2)
                    } else {
                        Text("Clipboard empty — type a prompt below").foregroundStyle(.secondary)
                    }
                }
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)

                if contextText != nil && !isResolvingContext && !ignoreClipboard {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { showFullContext.toggle() } } label: {
                        Image(systemName: showFullContext ? "eye.slash" : "eye")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help(showFullContext ? "Hide content" : "Show content")
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func maskedPreview(_ text: String) -> String {
        if showFullContext {
            return text.count > 400 ? String(text.prefix(400)) + "…" : text
        }
        let prefix = String(text.prefix(3))
        let bullets = String(repeating: "•", count: min(max(text.count - 3, 0), 24))
        return prefix + bullets
    }

    // MARK: - Prompt field

    private var promptField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble").foregroundStyle(.secondary).font(.caption).padding(.top, 2)
            TextField("Prompt…", text: $userPrompt, axis: .vertical)
                .focused($promptFocused)
                .font(.caption)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity)
                .onSubmit { runFirstAction() }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Option checkboxes

    @ViewBuilder
    private var optionCheckboxes: some View {
        HStack(spacing: 16) {
            if hasSessionFolder {
                Toggle(isOn: $recordThisSession) {
                    Label("Record", systemImage: "square.and.arrow.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Save input and output to session log")
            }

            // "Also send image" — visible when OCR found text but original image is available
            if !ignoreClipboard, contextIsFromOCR, ocrSourceImageData != nil {
                Toggle(isOn: $sendOCRImage) {
                    Label("Send image", systemImage: "photo")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Also send the source image to the model alongside the OCR text")
            }

            // Load URL — always visible so user can enable it for any clipboard text
            if !ignoreClipboard {
                Toggle(isOn: $loadURL) {
                    Label("Load URL", systemImage: "globe")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .disabled(loadURLAuto)   // auto-checked for pure-URL clipboard, user can't uncheck
                .help(loadURLAuto
                      ? "Clipboard is a URL — page will be fetched automatically"
                      : "Fetch content of URL(s) found in clipboard and append to context")
            }

            Toggle(isOn: $ignoreClipboard) {
                Label("Ignore clipboard", systemImage: "doc.on.clipboard.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Skip clipboard; run agent with prompt only")
            .onChange(of: ignoreClipboard) { _, _ in showFullContext = false }

            Toggle(isOn: $readOutput) {
                Label("Read aloud", systemImage: "speaker.wave.2")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Read the result via text-to-speech")

            if speech.isSpeaking {
                Button("Stop") { speech.stop() }
                    .font(.caption2).buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = engine.fetchStatus {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
            }

            if contextIsFromOCR && !ignoreClipboard {
                actionButton(title: "Recognise text (OCR)", missingKey: false, isRunning: false, keyHint: nil) {
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
                    Button {
                        editingAction = action
                    } label: {
                        Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit action \(action.name)")
                    .disabled(engine.isLoading)
                }
            }

            if actions.isEmpty {
                Text("No actions — add one in Settings → Actions")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if engine.isLoading {
                HStack { Spacer(); Button("Cancel") { engine.cancel() }.buttonStyle(.bordered) }
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
        .disabled(!canRun)
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
                    if let action = lastAction { Button("Retry") { runAction(action) } }
                    if isMissingKeyError {
                        Button("Settings") { withAnimation { showingSettings = true } }
                    }
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
                    Spacer()
                    Button(didCopy ? "Copied ✓" : "Copy") { copyResult() }
                        .keyboardShortcut("c", modifiers: .command)
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentInput: String { effectiveContext ?? userPrompt }

    private func hasKey(for action: Action) -> Bool {
        let config = ConfigStore.shared.config
        if !action.provider.isEmpty,
           let uuid = UUID(uuidString: action.provider),
           let prov = config.providers.first(where: { $0.id == uuid }) {
            return KeychainStore.hasKey(forProviderID: prov.id)
        }
        if config.providers.count == 1 {
            return KeychainStore.hasKey(forProviderID: config.providers[0].id)
        }
        return false
    }

    private func resolveVariables(in prompt: String) -> String {
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .none; df.locale = Locale.current
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return prompt
            .replacingOccurrences(of: "{{datum}}", with: df.string(from: Date()))
            .replacingOccurrences(of: "{{jazyk}}", with: lang)
            .replacingOccurrences(of: "{{kontext}}", with: userPrompt)
    }

    private func resolveContext() {
        promptFocused = false
        engine.reset()
        speech.stop()
        contextText = nil
        didCopy = false
        shownHistoryResult = nil
        showHistory = false
        showFullContext = false

        isResolvingContext = true
        ocrSourceImageData = nil
        sendOCRImage = false
        let pb = NSPasteboard.general
        contextIsFromOCR = pb.string(forType: .string)?.isEmpty != false && NSImage(pasteboard: pb) != nil
        Task {
            let result = await ContextResolver.resolve()
            switch result {
            case .text(let text, let isOCR):
                contextText = text
                contextImageData = nil
                ocrSourceImageData = nil
                contextIsFromOCR = isOCR
                let isPureURL = WebFetcher.isURL(text.trimmingCharacters(in: .whitespacesAndNewlines))
                loadURLAuto = isPureURL
                loadURL = isPureURL
            case .textWithImage(let text, let data, let mime):
                contextText = text
                contextImageData = nil
                ocrSourceImageData = data
                ocrSourceMimeType = mime
                contextIsFromOCR = true
                loadURLAuto = false
                loadURL = false
            case .image(let data, let mime):
                contextText = nil
                contextImageData = data
                contextMimeType = mime
                ocrSourceImageData = nil
                contextIsFromOCR = false
                loadURLAuto = false
                loadURL = false
            case .error:
                contextText = nil
                contextImageData = nil
                ocrSourceImageData = nil
                loadURLAuto = false
                loadURL = false
            }
            isResolvingContext = false
        }
    }

    private func runFirstAction() {
        guard let action = actions.first, canRun else { return }
        runAction(action)
    }

    private func runAction(_ action: Action) {
        promptFocused = false
        lastAction = action
        didCopy = false
        shownHistoryResult = nil
        var resolved = action
        resolved.systemPrompt = resolveVariables(in: action.systemPrompt)

        let input: String
        if let text = effectiveContext, !text.isEmpty {
            if !userPrompt.isEmpty && !action.systemPrompt.contains("{{kontext}}") {
                input = text + "\n\n---\n" + userPrompt
            } else {
                input = text
            }
        } else if !userPrompt.isEmpty {
            input = userPrompt
        } else {
            return
        }
        // Determine image to send:
        //  • pure-image clipboard → contextImageData
        //  • OCR + "Send image" checkbox → ocrSourceImageData
        let imgData: Data?
        let imgMime: String?
        if ignoreClipboard {
            imgData = nil; imgMime = nil
        } else if let data = contextImageData {
            imgData = data; imgMime = contextMimeType
        } else if sendOCRImage, let data = ocrSourceImageData {
            imgData = data; imgMime = ocrSourceMimeType
        } else {
            imgData = nil; imgMime = nil
        }
        engine.run(action: resolved, input: input, recordSession: recordThisSession,
                   loadURL: loadURL && !ignoreClipboard,
                   imageData: imgData, imageMimeType: imgMime)
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
            HStack { Text("Edit action").font(.headline); Spacer() }.padding()
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
            HStack { Spacer(); Button("Done") { onDone() }.buttonStyle(.borderedProminent) }.padding()
        }
        .frame(width: 560, height: 440)
    }
}
