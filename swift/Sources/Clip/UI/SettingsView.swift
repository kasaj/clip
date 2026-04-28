import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config = ConfigStore.shared.config
    @State private var launchAtLogin = false
    @State private var importedActions: [Action] = []
    @State private var showImportAlert = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            actionsTab.tabItem { Label("Actions", systemImage: "list.bullet") }
            providersTab.tabItem { Label("Providers", systemImage: "key") }
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: .infinity,
               minHeight: 480, idealHeight: 580, maxHeight: .infinity)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = !enabled }
                    }
                Toggle("Copy result and close panel after action completes", isOn: $config.autoCopyAndClose)
                    .onChange(of: config.autoCopyAndClose) { _, val in ConfigStore.shared.update { $0.autoCopyAndClose = val } }
                Stepper("Result history: \(config.historyLimit == 0 ? "off" : "\(config.historyLimit)")",
                        value: $config.historyLimit, in: 0...10)
                    .onChange(of: config.historyLimit) { _, val in
                        ConfigStore.shared.update { $0.historyLimit = val }
                        HistoryStore.shared.trim(to: val)
                    }
            }

            Section("Global shortcut") {
                HStack {
                    Text("Shortcut"); Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode)  { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
                Text("Click the field and press the desired key combination.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Config folder") {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(config.configFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not selected")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(config.configFolderPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { pickConfigFolder() }
                    if config.configFolderPath != nil {
                        Button("Clear") {
                            config.configFolderPath = nil
                            ConfigStore.shared.update { $0.configFolderPath = nil }
                        }
                        .foregroundStyle(.red)
                    }
                }
                if let p = config.configFolderPath {
                    Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Text("Actions (agents.json) and providers (providers.json) are read from this folder and written back. Useful for sync via iDrive / OneDrive.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Everything is stored locally in ~/Library/Application Support/Clip/.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Sessions folder") {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                    Text(config.sessionFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not selected")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(config.sessionFolderPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { pickSessionFolder() }
                    if config.sessionFolderPath != nil {
                        Button("Clear") {
                            config.sessionFolderPath = nil
                            ConfigStore.shared.update { $0.sessionFolderPath = nil }
                        }
                        .foregroundStyle(.red)
                    }
                }
                if let p = config.sessionFolderPath {
                    Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Text("Sessions are saved as Markdown files (YYYY-MM-DD.md) in this folder. Ideal for Obsidian or iCloud.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let p = config.configFolderPath, !p.isEmpty {
                    Text("Sessions are saved to: \(p)/sessions/ (from config folder).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sessions disabled — choose a config folder or a custom sessions folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Always record sessions automatically", isOn: $config.recordSessions)
                    .onChange(of: config.recordSessions) { _, val in ConfigStore.shared.update { $0.recordSessions = val } }
                    .disabled(config.sessionFolderPath == nil && (config.configFolderPath ?? "").isEmpty)
            }

            Section("About") {
                HStack(spacing: 8) {
                    Text("Clip").font(.headline)
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Link("github.com/kasaj/clip", destination: URL(string: "https://github.com/kasaj/clip")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped).padding()
    }

    private func saveHotkey() {
        ConfigStore.shared.update { $0.hotkeyKeyCode = config.hotkeyKeyCode; $0.hotkeyModifiers = config.hotkeyModifiers }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    private func pickConfigFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select config folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let path = url.path
            DispatchQueue.main.async {
                config.configFolderPath = path
                ConfigStore.shared.update { $0.configFolderPath = path }
                ConfigStore.shared.reloadFromFolder()
                config = ConfigStore.shared.config
            }
        }
    }

    private func pickSessionFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select sessions folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let path = url.path
            DispatchQueue.main.async {
                config.sessionFolderPath = path
                ConfigStore.shared.update { $0.sessionFolderPath = path }
                config = ConfigStore.shared.config
            }
        }
    }

    // MARK: - Actions Tab

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($config.actions) { $action in
                    ActionRow(action: $action, onDelete: {
                        config.actions.removeAll { $0.id == action.id }
                        ConfigStore.shared.update { $0.actions = config.actions }
                    })
                }
                .onMove { from, to in
                    config.actions.move(fromOffsets: from, toOffset: to)
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
            }
            .onChange(of: config.actions) { _, actions in
                ConfigStore.shared.update { $0.actions = actions }
            }
            Divider()
            HStack {
                Button("Add action") {
                    let firstProviderID = config.providers.first?.id ?? Provider.claudeAzureID
                    config.actions.append(Action(name: "New action", systemPrompt: "",
                                                 provider: firstProviderID, model: "", enabled: true))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button("Import…") { importActions() }
                Button("Export…") { exportActions() }.disabled(config.actions.isEmpty)
            }
            .padding(12)
        }
        .alert("Import actions", isPresented: $showImportAlert) {
            Button("Add to existing") {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions.append(contentsOf: fresh)
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Replace all", role: .destructive) {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions = fresh
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Found \(importedActions.count) action(s). Add to existing or replace all?")
        }
    }

    private func exportActions() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.actions) else { return }
        let panel = NSSavePanel(); panel.title = "Export actions"; panel.nameFieldStringValue = "agents.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in guard response == .OK, let url = panel.url else { return }; try? data.write(to: url, options: .atomic) }
    }

    private func importActions() {
        let panel = NSOpenPanel(); panel.title = "Import actions"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let actions = try? JSONDecoder().decode([Action].self, from: data), !actions.isEmpty else { return }
            DispatchQueue.main.async { importedActions = actions; showImportAlert = true }
        }
    }

    // MARK: - Providers Tab

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($config.providers) { $provider in
                    ProviderRow(
                        provider: $provider,
                        onDelete: {
                            config.providers.removeAll { $0.id == provider.id }
                            ConfigStore.shared.update { $0.providers = config.providers }
                        },
                        onChange: {
                            if provider.isDefault {
                                for i in config.providers.indices where config.providers[i].id != provider.id {
                                    config.providers[i].isDefault = false
                                }
                            }
                            ConfigStore.shared.update { $0.providers = config.providers }
                            config = ConfigStore.shared.config
                        }
                    )
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button("+ Add provider") {
                    config.providers.append(Provider.template(kind: .openai))
                    ConfigStore.shared.update { $0.providers = config.providers }
                }
                Spacer()
                if let folderPath = config.configFolderPath, !folderPath.isEmpty {
                    Button {
                        let url = URL(fileURLWithPath: folderPath)
                            .appendingPathComponent("providers.json")
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: folderPath)])
                        }
                    } label: {
                        Label("providers.json", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
                Text("\(config.providers.count) provider(s)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

// MARK: - Provider test state

enum ProviderTestState {
    case idle
    case testing
    case success(String)
    case failure(String)

    var color: Color {
        switch self {
        case .idle, .testing: .secondary
        case .success: .green
        case .failure: .red
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    @Binding var provider: Provider
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var expanded = false
    @State private var confirmDelete = false
    @State private var testState: ProviderTestState = .idle
    @State private var idField = ""
    @State private var keyField = ""
    @State private var keySaved: Bool? = nil
    @State private var urlField = ""
    @State private var modelField = ""
    @State private var deploymentField = ""
    @State private var apiVersionField = ""
    @State private var orgIdField = ""

    private var hasKey: Bool {
        (provider.apiKey?.isEmpty == false) || KeychainStore.hasKey(forProviderID: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name).font(.callout).fontWeight(.medium)
                        if !provider.enabled {
                            Text("disabled").font(.caption2).foregroundStyle(.secondary)
                        }
                        if provider.isDefault {
                            Text("default").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(provider.kind.displayName).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: hasKey ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundStyle(hasKey ? .green : .secondary)

                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete provider \"\(provider.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
            .padding(.vertical, 8)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    providerField("ID") {
                        TextField("provider-id", text: $idField)
                            .onChange(of: idField) {
                                let newID = idField.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !newID.isEmpty, newID != provider.id else { return }
                                ConfigStore.shared.update { cfg in
                                    for i in cfg.actions.indices where cfg.actions[i].provider == provider.id {
                                        cfg.actions[i].provider = newID
                                    }
                                }
                                provider.id = newID
                                onChange()
                            }
                        Text("(used as reference in actions)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    providerField("Name") {
                        TextField("Provider name", text: $provider.name)
                            .onChange(of: provider.name) { onChange() }
                    }

                    providerField("Type") {
                        Picker("", selection: $provider.kind) {
                            ForEach(ProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().frame(width: 200)
                        .onChange(of: provider.kind) { _, newKind in
                            let t = Provider.template(kind: newKind, name: provider.name)
                            provider.baseURL        = t.baseURL
                            provider.model          = t.model
                            provider.deploymentName = t.deploymentName
                            provider.apiVersion     = t.apiVersion
                            provider.defaults       = t.defaults
                            syncFields()
                            onChange()
                        }
                    }

                    providerField("API Key") {
                        SecureField("API key", text: $keyField).onSubmit { saveKey() }
                        Button("Save") { saveKey() }.disabled(keyField.isEmpty)
                        if let saved = keySaved {
                            Image(systemName: saved ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(saved ? .green : .red)
                        }
                    }

                    providerField("URL") {
                        TextField(provider.kind == .anthropic
                            ? "https://api.anthropic.com"
                            : provider.kind == .openai
                                ? "https://api.openai.com/v1"
                                : "https://RESOURCE.openai.azure.com/openai/v1",
                            text: $urlField)
                            .onChange(of: urlField) {
                                provider.baseURL = urlField.isEmpty ? nil : urlField
                                onChange()
                            }
                    }

                    if provider.kind == .openai {
                        providerField("Org ID") {
                            TextField("org-... (optional)", text: $orgIdField)
                                .onChange(of: orgIdField) {
                                    provider.organizationId = orgIdField.isEmpty ? nil : orgIdField
                                    onChange()
                                }
                        }
                    }

                    providerField(provider.kind == .custom ? "Deployment" : "Model") {
                        TextField(provider.kind == .custom
                            ? "deployment-name  (from Azure portal)"
                            : provider.kind == .openai ? "gpt-4o" : "claude-sonnet-4-20250514",
                            text: $modelField)
                            .onChange(of: modelField) {
                                provider.model = modelField.isEmpty ? nil : modelField
                                onChange()
                            }
                    }

                    if provider.kind == .custom {
                        providerField("API version") {
                            TextField("2024-02-01  (legacy deployment URL style only)", text: $apiVersionField)
                                .onChange(of: apiVersionField) {
                                    provider.apiVersion = apiVersionField.isEmpty ? nil : apiVersionField
                                    onChange()
                                }
                        }
                    }

                    HStack(spacing: 16) {
                        Text("").frame(width: 72)
                        Toggle("Active", isOn: $provider.enabled)
                            .font(.caption).onChange(of: provider.enabled) { onChange() }
                        Toggle("Default", isOn: $provider.isDefault)
                            .font(.caption).onChange(of: provider.isDefault) { onChange() }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("").frame(width: 72)
                        Button {
                            Task { await runTest() }
                        } label: {
                            if case .testing = testState {
                                HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Testing…") }
                            } else {
                                Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .disabled({ if case .testing = testState { true } else { false } }())
                        switch testState {
                        case .idle, .testing: EmptyView()
                        case .success(let msg):
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(msg).font(.caption).foregroundStyle(.green).lineLimit(2)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 20).padding(.bottom, 8)
            }
        }
        .onAppear { syncFields() }
    }

    @ViewBuilder
    private func providerField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
            content()
        }
    }

    private func syncFields() {
        idField         = provider.id
        keyField        = provider.apiKey ?? (try? KeychainStore.load(forProviderID: provider.id)) ?? ""
        urlField        = provider.baseURL ?? ""
        modelField      = provider.model ?? ""
        deploymentField = provider.deploymentName ?? ""
        apiVersionField = provider.apiVersion ?? ""
        orgIdField      = provider.organizationId ?? ""
    }

    private func saveKey() {
        guard !keyField.isEmpty else { return }
        do {
            provider.apiKey = keyField
            try KeychainStore.save(apiKey: keyField, forProviderID: provider.id)
            keySaved = true; onChange()
        } catch { keySaved = false }
    }

    private func runTest() async {
        testState = .testing
        do {
            let reply = try await ProviderFactory.test(provider: provider)
            testState = .success(reply.prefix(80).description)
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Action Row (shared with OverlayView inline edit)

struct ActionRow: View {
    @Binding var action: Action
    var onDelete: (() -> Void)? = nil
    @State private var pickerModel: String = ""
    @State private var customModelText: String = ""
    @State private var confirmDelete = false
    private let customSentinel = "__custom__"
    private var isCustom: Bool { pickerModel == customSentinel }

    private var resolvedProvider: Provider? {
        guard !action.provider.isEmpty else { return nil }
        return ConfigStore.shared.config.providers.first(where: { $0.id == action.provider })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $action.enabled).labelsHidden()
                TextField("Action name", text: $action.name).font(.headline)
                Spacer()
                if let del = onDelete {
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete action \"\(action.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { del() }
                    }
                }
            }
            providerModelRow
            TextEditor(text: $action.systemPrompt)
                .font(.callout).frame(minHeight: 60, maxHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            parametersRow
        }
        .padding(.vertical, 6)
        .onAppear { syncPickerFromAction() }
        .onChange(of: action.provider) { syncPickerFromAction() }
    }

    private func syncPickerFromAction() {
        guard let prov = resolvedProvider else { pickerModel = customSentinel; customModelText = action.model; return }
        let presets = prov.effectiveModels(using: ConfigStore.shared.config.modelPresets)
        if !presets.isEmpty && presets.contains(where: { $0.id == action.model }) {
            pickerModel = action.model; customModelText = ""
        } else {
            pickerModel = customSentinel; customModelText = action.model
        }
    }

    private var providerModelRow: some View {
        let providers = ConfigStore.shared.config.providers
        let models = resolvedProvider?.effectiveModels(using: ConfigStore.shared.config.modelPresets) ?? []

        return HStack(spacing: 6) {
            Picker("Provider", selection: $action.provider) {
                ForEach(providers) { p in Text(p.name).tag(p.id) }
            }
            .labelsHidden().frame(width: 160)
            .onChange(of: action.provider) {
                let presets = resolvedProvider?.effectiveModels(using: ConfigStore.shared.config.modelPresets) ?? []
                if presets.isEmpty { action.model = ""; pickerModel = customSentinel; customModelText = "" }
                else { let f = presets.first!.id; action.model = f; pickerModel = f; customModelText = "" }
            }

            if models.isEmpty {
                TextField("model name", text: $customModelText).frame(minWidth: 200)
                    .onChange(of: customModelText) { if !customModelText.isEmpty { action.model = customModelText } }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(models) { preset in
                        Text(preset.isRecommended ? "\(preset.displayName) ★" : preset.displayName).tag(preset.id)
                    }
                    Divider()
                    Text("Custom model…").tag(customSentinel)
                }
                .labelsHidden().frame(minWidth: 240)
                .onChange(of: pickerModel) { if pickerModel != customSentinel { action.model = pickerModel; customModelText = "" } }
                if isCustom {
                    TextField("model name", text: $customModelText).frame(minWidth: 180)
                        .onChange(of: customModelText) { if !customModelText.isEmpty { action.model = customModelText } }
                }
            }
        }
    }

    private var parametersRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperature: \(action.temperature, specifier: "%.1f")").font(.caption).foregroundStyle(.secondary)
                Slider(value: $action.temperature, in: 0.0...2.0, step: 0.1).frame(width: 140)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Copy & close").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $action.autoCopyClose) {
                    ForEach(AutoCopyClose.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 120).pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Max tokens").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("", value: $action.maxTokens, format: .number).frame(width: 72).multilineTextAlignment(.trailing)
                    Stepper("", value: $action.maxTokens, in: 256...32000, step: 256).labelsHidden()
                }
            }
        }
    }
}
