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

    // History
    @State private var shownHistoryResult: String?

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
            if editingAction != nil {
                actionEditPanel
            } else {
                overlayContent
            }
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: .infinity,
               minHeight: 380, idealHeight: 620, maxHeight: .infinity)
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
        .onChange(of: recordThisSession) { _, record in
            // If the user turns Record ON after the output already arrived, save now
            guard record, !engine.result.isEmpty, let action = lastAction else { return }
            let cfg = ConfigStore.shared.config
            let prov = cfg.providers.first(where: { $0.id == action.provider })
            let providerName = prov?.name ?? action.provider
            let model = action.model.isEmpty ? (prov?.model ?? "") : action.model
            SessionStore.shared.save(
                agent: action.name,
                provider: providerName,
                model: model,
                input: currentInput,
                output: engine.result,
                duration: 0
            )
        }
        .onKeyPress(.escape) {
            if editingAction != nil { editingAction = nil; return .handled }
            close(); return .handled
        }
        .onKeyPress { press in
            guard !promptFocused, editingAction == nil,
                  let digit = Int(press.characters),
                  digit >= 1, digit <= actions.count else { return .ignored }
            runAction(actions[digit - 1])
            return .handled
        }
        // Save action edits back to ConfigStore whenever editingAction changes
        .onChange(of: editingAction) { _, action in
            guard let action else { return }
            ConfigStore.shared.update { store in
                if let idx = store.actions.firstIndex(where: { $0.id == action.id }) {
                    store.actions[idx] = action
                }
            }
        }
    }

    // MARK: - Close (stops speech + resets transient state)

    private func close() {
        SpeechPlayer.shared.stop()
        PopupWindowManager.closeAll()
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
        shownHistoryResult = nil
        engine.reset()
    }

    // MARK: - Overlay content

    private var overlayContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                contextPreview
                promptField
                optionCheckboxes
                actionButtons
            }
            .padding(16)
            .layoutPriority(0)
            Divider()
            resultArea
                .padding(16)
                .frame(minHeight: 200, maxHeight: .infinity)
                .layoutPriority(1)
        }
    }

    // MARK: - Inline action editor (replaces sheet to avoid floating-panel close bug)

    private var actionEditPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { editingAction = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.subheadline)
                        Text("Back").font(.subheadline)
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text(editingAction?.name ?? "Action").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            ScrollView {
                ActionRow(action: Binding(
                    get: { editingAction ?? Action(name: "", systemPrompt: "", provider: "", model: "", enabled: true) },
                    set: { editingAction = $0 }
                ))
                .padding(16)
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
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16).padding(.vertical, 3)
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
        } else if ignoreClipboard {
            statusRow("Clipboard ignored — prompt only", icon: "doc.on.clipboard")
        } else if isResolvingContext {
            statusRow(contextIsFromOCR ? "Reading image…" : "Reading clipboard…", icon: "ellipsis")
        } else if let text = contextText {
            HStack(spacing: 6) {
                Image(systemName: contextIsFromOCR ? "doc.viewfinder" : "doc.on.clipboard")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Clipboard — \(text.count) chars").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    PopupWindowManager.showClipboard(text: text)
                } label: {
                    Image(systemName: "eye")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show clipboard content")
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            statusRow("Clipboard empty — type a prompt below", icon: "doc.on.clipboard")
        }
    }

    private func statusRow(_ message: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        HStack(spacing: 12) {
            if hasSessionFolder {
                Toggle(isOn: $recordThisSession) {
                    Label("Record", systemImage: "square.and.arrow.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Save input and output to session log")
            }

            let hasURLs = !ignoreClipboard && (contextText.map { WebFetcher.containsAnyURL($0) } ?? false)
            Toggle(isOn: $loadURL) {
                Label("URLFetch", systemImage: "globe")
                    .font(.caption2)
                    .foregroundStyle(hasURLs ? Color.accentColor : Color.secondary)
            }
            .toggleStyle(.checkbox)
            .disabled(loadURLAuto)
            .help(loadURLAuto
                  ? "Clipboard contains URL — page will be loaded automatically"
                  : "Load URL content from clipboard and add to context")

            let hasClipboard = (contextText != nil || contextImageData != nil) && !isResolvingContext && !ignoreClipboard
            Toggle(isOn: $ignoreClipboard) {
                Label("Ignore", systemImage: "doc.on.clipboard.fill")
                    .font(.caption2)
                    .foregroundStyle(hasClipboard ? Color.accentColor : Color.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Ignore clipboard; run with prompt only")
            .onChange(of: ignoreClipboard) { _, _ in }

            Toggle(isOn: $readOutput) {
                Label("Read", systemImage: "speaker.wave.2")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Read result aloud (TTS)")

            // "+ image" — always visible; active when OCR image is available
            let imageAvailable = contextIsFromOCR && ocrSourceImageData != nil && !ignoreClipboard
            Toggle(isOn: $sendOCRImage) {
                Label("+ image", systemImage: "photo")
                    .font(.caption2).foregroundStyle(imageAvailable ? Color.accentColor : Color.secondary)
            }
            .toggleStyle(.checkbox)
            .disabled(!imageAvailable)
            .help(imageAvailable
                  ? "Attach source image alongside OCR text"
                  : "Clipboard does not contain an image with text")

            // OCR button — always visible
            let ocrReady = contextIsFromOCR && contextText != nil && !ignoreClipboard
            Button {
                if let text = contextText { engine.showText(text) }
            } label: {
                Label("OCR", systemImage: "doc.viewfinder")
                    .font(.caption2)
                    .foregroundStyle(ocrReady ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!ocrReady)
            .help(ocrReady
                  ? "Show recognised text from image"
                  : "Clipboard does not contain an image with recognisable text")

            if speech.isSpeaking {
                Button("Stop") { speech.stop() }
                    .font(.caption2).buttonStyle(.bordered).controlSize(.small)
            }

            Spacer()

            // History button — same style as other labels, blue when has entries
            if ConfigStore.shared.config.historyLimit > 0 {
                let hasHistory = !history.entries.isEmpty
                Button {
                    PopupWindowManager.showHistory { selected in
                        shownHistoryResult = selected
                    }
                } label: {
                    Label("History", systemImage: hasHistory ? "clock.fill" : "clock")
                        .font(.caption2)
                        .foregroundStyle(hasHistory ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Show history")
            }
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

            // Three-column grid — each button one-third width
            let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    HStack(spacing: 4) {
                        actionButton(
                            title: action.name,
                            missingKey: !hasKey(for: action),
                            isRunning: engine.isLoading && lastAction == action,
                            keyHint: index < 9 ? String(index + 1) : nil
                        ) { runAction(action) }
                        Button {
                            editingAction = action
                        } label: {
                            Image(systemName: "gearshape").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit action \(action.name)")
                        .disabled(engine.isLoading)
                    }
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
                        Button("Settings") { (NSApp.delegate as? AppDelegate)?.openSettings() }
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
            } else {
                // Placeholder — always show output area so window stays the same size
                Text(engine.isLoading ? "" : "Result will appear here…")
                    .font(.caption)
                    .foregroundStyle(Color(.placeholderTextColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private var currentInput: String { effectiveContext ?? userPrompt }

    private func hasKey(for action: Action) -> Bool {
        let config = ConfigStore.shared.config
        if !action.provider.isEmpty,
           let prov = config.providers.first(where: { $0.id == action.provider }) {
            return (prov.apiKey?.isEmpty == false) || KeychainStore.hasKey(forProviderID: prov.id)
        }
        if config.providers.count == 1 {
            let p = config.providers[0]
            return (p.apiKey?.isEmpty == false) || KeychainStore.hasKey(forProviderID: p.id)
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

        // Prompt-only mode: no clipboard context at all → bypass action's system prompt
        // so the user's prompt is sent directly as the primary instruction, not as
        // data to be processed by a grammar-fixer / translator / etc.
        if effectiveContext == nil && contextImageData == nil {
            resolved.systemPrompt = ""
        }

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

// MARK: - Popup Window Manager

@MainActor
enum PopupWindowManager {
    private static var clipboardWindow: NSWindow?
    private static var historyWindow: NSWindow?

    static func showClipboard(text: String) {
        if let w = clipboardWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil); return
        }
        let view = ClipboardPreviewWindowView(text: text)
        clipboardWindow = makePanel(rootView: view, title: "Clipboard", width: 540, height: 400)
        clipboardWindow?.makeKeyAndOrderFront(nil)
    }

    static func showHistory(onSelect: @escaping (String) -> Void) {
        if let w = historyWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil); return
        }
        let view = HistoryWindowView(onSelect: { result in
            onSelect(result)
            historyWindow?.orderOut(nil)
        })
        historyWindow = makePanel(rootView: view, title: "History", width: 460, height: 340)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeAll() {
        clipboardWindow?.orderOut(nil)
        historyWindow?.orderOut(nil)
    }

    private static func makePanel<V: View>(rootView: V, title: String, width: CGFloat, height: CGFloat) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.isRestorable = false
        w.contentView = NSHostingView(rootView: rootView.ignoresSafeArea())
        w.center()
        return w
    }
}

// MARK: - Clipboard Preview Window

private struct ClipboardPreviewWindowView: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Clipboard", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                Text("\(text.count) chars").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}

// MARK: - History Window

private struct HistoryWindowView: View {
    @ObservedObject private var history = HistoryStore.shared
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("History", systemImage: "clock")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if history.entries.isEmpty {
                Spacer()
                Text("No history yet").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(history.entries) { entry in
                    Button {
                        onSelect(entry.result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.actionName).font(.callout).fontWeight(.medium)
                                Spacer()
                                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(entry.inputSnippet)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 200)
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
