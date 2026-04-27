import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config = ConfigStore.shared.config
    @State private var keySaveStatus: [UUID: Bool] = [:]
    @State private var launchAtLogin = false
    @State private var importedActions: [Action] = []
    @State private var showImportAlert = false
    @State private var isFetching: UUID? = nil
    @State private var fetchError: [UUID: String] = [:]
    @State private var reviewModels: [FetchedModel] = []
    @State private var reviewingProvider: Provider? = nil

    var body: some View {
        TabView {
            generalTab.tabItem { Label("Obecné", systemImage: "gearshape") }
            actionsTab.tabItem { Label("Akce", systemImage: "list.bullet") }
            providersTab.tabItem { Label("Providery", systemImage: "key") }
        }
        .frame(width: 700, height: 580)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .sheet(item: $reviewingProvider) { provider in
            ModelReviewSheet(provider: provider, models: $reviewModels) { saved in
                let presets = saved.filter(\.isIncluded)
                    .map { ModelPreset(id: $0.id, displayName: $0.displayName, isRecommended: $0.isRecommended) }
                ConfigStore.shared.update { $0.modelPresets[provider.id.uuidString] = presets }
                config = ConfigStore.shared.config
                reviewingProvider = nil
            } onCancel: { reviewingProvider = nil }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Spustit při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = !enabled }
                    }
                Toggle("Po dokončení akce zkopírovat výsledek a zavřít panel", isOn: $config.autoCopyAndClose)
                    .onChange(of: config.autoCopyAndClose) { _, val in ConfigStore.shared.update { $0.autoCopyAndClose = val } }
                Stepper("Historie výsledků: \(config.historyLimit == 0 ? "vypnuto" : "\(config.historyLimit)")",
                        value: $config.historyLimit, in: 0...10)
                    .onChange(of: config.historyLimit) { _, val in
                        ConfigStore.shared.update { $0.historyLimit = val }
                        HistoryStore.shared.trim(to: val)
                    }
            }

            Section("Globální zkratka") {
                HStack {
                    Text("Zkratka"); Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode)  { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
                Text("Klikni na pole a stiskni požadovanou kombinaci kláves.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Složka konfigurace") {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(config.configFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Nevybráno")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(config.configFolderPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Vybrat…") { pickConfigFolder() }
                    if config.configFolderPath != nil {
                        Button("Zrušit") {
                            config.configFolderPath = nil
                            ConfigStore.shared.update { $0.configFolderPath = nil }
                        }
                        .foregroundStyle(.red)
                    }
                }
                if let p = config.configFolderPath {
                    Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Text("Agenti (agents.json) a providery (providers.json) se čtou z této složky a zapisují zpět. Slouží pro sync přes iDrive / OneDrive.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Vše se ukládá lokálně do ~/Library/Application Support/Clip/.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Složka záznamů (sessions)") {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                    Text(config.sessionFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Nevybráno")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(config.sessionFolderPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Vybrat…") { pickSessionFolder() }
                    if config.sessionFolderPath != nil {
                        Button("Zrušit") {
                            config.sessionFolderPath = nil
                            ConfigStore.shared.update { $0.sessionFolderPath = nil }
                        }
                        .foregroundStyle(.red)
                    }
                }
                if let p = config.sessionFolderPath {
                    Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Text("Záznamy se ukládají jako Markdown soubory (YYYY-MM-DD.md) do této složky. Ideální pro Obsidian nebo iCloud.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let p = config.configFolderPath, !p.isEmpty {
                    Text("Záznamy se ukládají do: \(p)/sessions/ (dle složky konfigurace).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Záznamy jsou vypnuty — vyber složku konfigurace nebo vlastní složku záznamů.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Vždy zaznamenávat operace automaticky", isOn: $config.recordSessions)
                    .onChange(of: config.recordSessions) { _, val in ConfigStore.shared.update { $0.recordSessions = val } }
                    .disabled(config.sessionFolderPath == nil && (config.configFolderPath ?? "").isEmpty)
            }

            Section("O aplikaci") {
                HStack(spacing: 8) {
                    Text("Clip")
                        .font(.headline)
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
        panel.title = "Vybrat složku konfigurace"
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
        panel.title = "Vybrat složku záznamů"
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
            Divider()
            HStack {
                Button("Přidat akci") {
                    let firstProviderID = config.providers.first?.id.uuidString ?? Provider.claudeAzureID.uuidString
                    config.actions.append(Action(name: "Nová akce", systemPrompt: "",
                                                 provider: firstProviderID, model: "", enabled: true))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button("Importovat…") { importActions() }
                Button("Exportovat…") { exportActions() }.disabled(config.actions.isEmpty)
            }
            .padding(12)
        }
        .alert("Importovat akce", isPresented: $showImportAlert) {
            Button("Přidat k existujícím") {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions.append(contentsOf: fresh)
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Nahradit vše", role: .destructive) {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions = fresh
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Nalezeno \(importedActions.count) \(importedActions.count == 1 ? "akce" : "akcí"). Přidat k existujícím, nebo nahradit vše?")
        }
    }

    private func exportActions() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.actions) else { return }
        let panel = NSSavePanel(); panel.title = "Exportovat akce"; panel.nameFieldStringValue = "agents.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in guard response == .OK, let url = panel.url else { return }; try? data.write(to: url, options: .atomic) }
    }

    private func importActions() {
        let panel = NSOpenPanel(); panel.title = "Importovat akce"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
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
                        keySaveStatus: $keySaveStatus,
                        isFetching: $isFetching,
                        fetchError: $fetchError,
                        onFetchModels: { Task { await fetchModels(for: provider) } },
                        onDelete: {
                            config.providers.removeAll { $0.id == provider.id }
                            ConfigStore.shared.update { $0.providers = config.providers }
                        },
                        onChange: {
                            ConfigStore.shared.update { $0.providers = config.providers }
                            config = ConfigStore.shared.config
                        }
                    )
                }
            }
            Divider()
            HStack {
                Button("+ Přidat provider") {
                    config.providers.append(Provider(name: "Nový provider", kind: .anthropic))
                    ConfigStore.shared.update { $0.providers = config.providers }
                }
                Spacer()
                Text("\(config.providers.count) providerů")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .sheet(item: $reviewingProvider) { provider in
            ModelReviewSheet(provider: provider, models: $reviewModels) { saved in
                let presets = saved.filter(\.isIncluded)
                    .map { ModelPreset(id: $0.id, displayName: $0.displayName, isRecommended: $0.isRecommended) }
                ConfigStore.shared.update { $0.modelPresets[provider.id.uuidString] = presets }
                config = ConfigStore.shared.config; reviewingProvider = nil
            } onCancel: { reviewingProvider = nil }
        }
    }

    private func fetchModels(for provider: Provider) async {
        isFetching = provider.id; fetchError[provider.id] = nil
        do {
            reviewModels = try await ModelFetcher.fetch(for: provider)
            reviewingProvider = provider
        } catch { fetchError[provider.id] = error.localizedDescription }
        isFetching = nil
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
    @Binding var keySaveStatus: [UUID: Bool]
    @Binding var isFetching: UUID?
    @Binding var fetchError: [UUID: String]
    let onFetchModels: () -> Void
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var expanded = false
    @State private var keyField = ""
    @State private var confirmDelete = false
    @State private var testState: ProviderTestState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header row
            HStack(spacing: 8) {
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name).font(.callout).fontWeight(.medium)
                    HStack(spacing: 6) {
                        Text(provider.kind.displayName).font(.caption2).foregroundStyle(.secondary)
                        if !provider.baseURL.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(provider.baseURL).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                // Key indicator
                Image(systemName: KeychainStore.hasKey(forProviderID: provider.id) ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundStyle(KeychainStore.hasKey(forProviderID: provider.id) ? .green : .secondary)

                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Smazat provider \"\(provider.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Smazat", role: .destructive) { onDelete() }
                }
            }
            .padding(.vertical, 8)

            // Expanded editor
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    HStack {
                        Text("Název").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        TextField("Název providera", text: $provider.name).onChange(of: provider.name) { onChange() }
                    }

                    HStack {
                        Text("Typ").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        Picker("", selection: $provider.kind) {
                            ForEach(ProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().frame(width: 200)
                        .onChange(of: provider.kind) { _, newKind in
                            // Auto-fill URL when type changes and URL is empty or was default
                            if provider.baseURL.isEmpty || ProviderKind.allCases.contains(where: { $0.defaultBaseURL == provider.baseURL }) {
                                provider.baseURL = newKind.defaultBaseURL
                            }
                            onChange()
                        }
                    }

                    HStack {
                        Text("Base URL").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        TextField(provider.kind.defaultBaseURL.isEmpty ? "https://..." : provider.kind.defaultBaseURL,
                                  text: $provider.baseURL)
                            .onChange(of: provider.baseURL) { onChange() }
                    }

                    HStack {
                        Text("API Version").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        TextField("pro Azure (např. 2024-10-21)", text: Binding(
                            get: { provider.apiVersion ?? "" },
                            set: { provider.apiVersion = $0.isEmpty ? nil : $0; onChange() }
                        ))
                    }

                    HStack(alignment: .center) {
                        Text("API Klíč").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        SecureField("API klíč", text: $keyField)
                            .onSubmit { saveKey() }
                        Button("Uložit") { saveKey() }.disabled(keyField.isEmpty)
                        if let saved = keySaveStatus[provider.id] {
                            Image(systemName: saved ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(saved ? .green : .red)
                        }
                    }

                    // Test connectivity
                    HStack(alignment: .firstTextBaseline) {
                        Text("").frame(width: 80)
                        Button {
                            Task { await runTest() }
                        } label: {
                            if case .testing = testState {
                                HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Testuji…") }
                            } else {
                                Label("Otestovat připojení", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .disabled({ if case .testing = testState { true } else { false } }())
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: EmptyView()
                        case .success(let msg):
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(msg).font(.caption).foregroundStyle(.green).lineLimit(2)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(3)
                        }
                    }

                    // Model fetch
                    if provider.kind != .custom {
                        HStack {
                            Text("").frame(width: 80)
                            Button {
                                onFetchModels()
                            } label: {
                                if isFetching == provider.id {
                                    HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Načítám…") }
                                } else {
                                    Label("Aktualizovat modely", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(isFetching != nil)
                        }
                        if let err = fetchError[provider.id] {
                            Text(err).font(.caption).foregroundStyle(.red).padding(.leading, 88)
                        }
                    }
                }
                .padding(.leading, 20).padding(.bottom, 8)
            }
        }
        .onAppear { keyField = (try? KeychainStore.load(forProviderID: provider.id)) ?? "" }
    }

    private func saveKey() {
        do {
            try KeychainStore.save(apiKey: keyField, forProviderID: provider.id)
            keySaveStatus[provider.id] = true
            onChange()
        } catch { keySaveStatus[provider.id] = false }
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

// MARK: - Model Review Sheet

private struct ModelReviewSheet: View {
    let provider: Provider
    @Binding var models: [FetchedModel]
    let onSave: ([FetchedModel]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Modely – \(provider.name)").font(.headline); Spacer() }.padding()
            Divider()
            List($models) { $model in
                HStack(spacing: 10) {
                    Toggle("", isOn: $model.isIncluded).labelsHidden()
                        .onChange(of: model.isIncluded) { _, included in if !included && model.isRecommended { model.isRecommended = false } }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName).strikethrough(!model.isIncluded, color: .secondary).foregroundStyle(model.isIncluded ? .primary : .secondary)
                        if model.inUseByAction { Text("Používáno v akci").font(.caption2).foregroundStyle(.orange) }
                    }
                    Spacer()
                    Button {
                        let t = model.id; for i in models.indices { models[i].isRecommended = models[i].id == t }
                    } label: {
                        Image(systemName: model.isRecommended ? "star.fill" : "star")
                            .foregroundStyle(model.isRecommended ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain).disabled(!model.isIncluded).help("Označit jako doporučený")
                }
            }
            Divider()
            HStack {
                Button("Zrušit", role: .cancel) { onCancel() }; Spacer()
                Text("\(models.filter(\.isIncluded).count) z \(models.count)").font(.caption).foregroundStyle(.secondary); Spacer()
                Button("Uložit") { onSave(models) }.buttonStyle(.borderedProminent).disabled(models.filter(\.isIncluded).isEmpty)
            }.padding()
        }
        .frame(width: 500, height: 440)
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
        guard let uuid = UUID(uuidString: action.provider) else { return nil }
        return ConfigStore.shared.config.providers.first(where: { $0.id == uuid })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $action.enabled).labelsHidden()
                TextField("Název akce", text: $action.name).font(.headline)
                Spacer()
                if let del = onDelete {
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Smazat akci \"\(action.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Smazat", role: .destructive) { del() }
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
                ForEach(providers) { p in Text(p.name).tag(p.id.uuidString) }
            }
            .labelsHidden().frame(width: 160)
            .onChange(of: action.provider) {
                let presets = resolvedProvider?.effectiveModels(using: ConfigStore.shared.config.modelPresets) ?? []
                if presets.isEmpty { action.model = ""; pickerModel = customSentinel; customModelText = "" }
                else { let f = presets.first!.id; action.model = f; pickerModel = f; customModelText = "" }
            }

            if models.isEmpty {
                TextField("název modelu", text: $customModelText).frame(width: 240)
                    .onChange(of: customModelText) { if !customModelText.isEmpty { action.model = customModelText } }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(models) { preset in
                        Text(preset.isRecommended ? "\(preset.displayName) ★" : preset.displayName).tag(preset.id)
                    }
                    Divider()
                    Text("Vlastní model…").tag(customSentinel)
                }
                .labelsHidden().frame(width: 200)
                .onChange(of: pickerModel) { if pickerModel != customSentinel { action.model = pickerModel; customModelText = "" } }
                if isCustom {
                    TextField("název modelu", text: $customModelText).frame(width: 140)
                        .onChange(of: customModelText) { if !customModelText.isEmpty { action.model = customModelText } }
                }
            }
        }
    }

    private var parametersRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Teplota: \(action.temperature, specifier: "%.1f")").font(.caption).foregroundStyle(.secondary)
                Slider(value: $action.temperature, in: 0.0...2.0, step: 0.1).frame(width: 140)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Zkopírovat a zavřít").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $action.autoCopyClose) {
                    ForEach(AutoCopyClose.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 120).pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Max. tokenů").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("", value: $action.maxTokens, format: .number).frame(width: 72).multilineTextAlignment(.trailing)
                    Stepper("", value: $action.maxTokens, in: 256...32000, step: 256).labelsHidden()
                }
            }
        }
    }
}

