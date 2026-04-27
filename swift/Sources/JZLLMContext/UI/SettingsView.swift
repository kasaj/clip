import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config = ConfigStore.shared.config
    @State private var azureAnthropicKey = ""
    @State private var anthropicKey = ""
    @State private var openaiKey = ""
    @State private var azureKey = ""
    @State private var azureKey2 = ""
    @State private var customKey = ""
    @State private var keySaveStatus: [ProviderType: Bool] = [:]
    @State private var launchAtLogin = false
    @State private var importedActions: [Action] = []
    @State private var showImportAlert = false
    @State private var isFetching: ProviderType? = nil
    @State private var fetchError: [ProviderType: String] = [:]
    @State private var reviewModels: [FetchedModel] = []
    @State private var reviewingProvider: ProviderType? = nil

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Obecné", systemImage: "gearshape") }
            actionsTab
                .tabItem { Label("Akce", systemImage: "list.bullet") }
            providersTab
                .tabItem { Label("Providery", systemImage: "key") }
        }
        .frame(width: 660, height: 560)
        .onAppear {
            loadKeys()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .sheet(item: $reviewingProvider) { provider in
            ModelReviewSheet(provider: provider, models: $reviewModels) { saved in
                let presets = saved
                    .filter(\.isIncluded)
                    .map { ModelPreset(id: $0.id, displayName: $0.displayName, isRecommended: $0.isRecommended) }
                ConfigStore.shared.update { $0.modelPresets[provider.rawValue] = presets }
                config = ConfigStore.shared.config
                reviewingProvider = nil
            } onCancel: {
                reviewingProvider = nil
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Spustit při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else       { try SMAppService.mainApp.unregister() }
                        } catch { launchAtLogin = !enabled }
                    }
                Toggle("Po dokončení akce zkopírovat výsledek a zavřít panel", isOn: $config.autoCopyAndClose)
                    .onChange(of: config.autoCopyAndClose) { _, val in
                        ConfigStore.shared.update { $0.autoCopyAndClose = val }
                    }
                Stepper("Historie výsledků: \(config.historyLimit == 0 ? "vypnuto" : "\(config.historyLimit)")",
                        value: $config.historyLimit, in: 0...10)
                    .onChange(of: config.historyLimit) { _, val in
                        ConfigStore.shared.update { $0.historyLimit = val }
                        HistoryStore.shared.trim(to: val)
                    }
            }

            Section("Globální zkratka") {
                HStack {
                    Text("Zkratka")
                    Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode)  { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
                Text("Klikni na pole a stiskni požadovanou kombinaci kláves. Kliknutí znovu zruší záznam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Složka konfigurace") {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(config.configFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Nevybráno")
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                    Text(p)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Agenti (agents.json) a endpointy (providers.json) se čtou z této složky a zapisují zpět. API klíče zůstávají v Keychain. Složku lze umístit na iDrive / OneDrive pro sync mezi zařízeními.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Vše se ukládá lokálně do ~/Library/Application Support/JZLLMContext/. Nastav složku na iDrive / OneDrive, aby se konfigurace synchronizovala mezi zařízeními.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveHotkey() {
        ConfigStore.shared.update {
            $0.hotkeyKeyCode  = config.hotkeyKeyCode
            $0.hotkeyModifiers = config.hotkeyModifiers
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    private func pickConfigFolder() {
        let panel = NSOpenPanel()
        panel.title = "Vybrat složku konfigurace"
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.canCreateDirectories  = true
        panel.allowsMultipleSelection = false
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
                    config.actions.append(Action(
                        name: "Nová akce", systemPrompt: "",
                        provider: .azureAnthropic, model: "claude-sonnet-4-6", enabled: true
                    ))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button("Importovat…") { importActions() }
                Button("Exportovat…") { exportActions() }
                    .disabled(config.actions.isEmpty)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.actions) else { return }
        let panel = NSSavePanel()
        panel.title = "Exportovat akce"
        panel.nameFieldStringValue = "agents.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importActions() {
        let panel = NSOpenPanel()
        panel.title = "Importovat akce"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let actions = try? JSONDecoder().decode([Action].self, from: data),
                  !actions.isEmpty else { return }
            DispatchQueue.main.async {
                importedActions = actions
                showImportAlert = true
            }
        }
    }

    // MARK: - Providers Tab

    private var providersTab: some View {
        Form {
            // ── Claude (Azure AI Foundry) ──────────────────────────────────
            Section("Claude (Azure AI Foundry)") {
                Text("Azure AI Foundry endpoint s Anthropic API. URL formát: https://<resource>.services.ai.azure.com/anthropic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API klíč", text: $azureAnthropicKey)
                    .onSubmit { saveKey(azureAnthropicKey, for: .azureAnthropic) }
                TextField("Endpoint", text: Binding(
                    get: { config.azureAnthropicEndpoint ?? "" },
                    set: {
                        config.azureAnthropicEndpoint = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAnthropicEndpoint = config.azureAnthropicEndpoint }
                    }
                ))
                TextField("API verze (výchozí: \(AppConfig.defaultAzureAPIVersion))", text: Binding(
                    get: { config.azureAnthropicAPIVersion ?? "" },
                    set: {
                        config.azureAnthropicAPIVersion = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAnthropicAPIVersion = config.azureAnthropicAPIVersion }
                    }
                ))
                saveButton(for: .azureAnthropic, key: azureAnthropicKey)
            }

            // ── Claude (Anthropic direct) ──────────────────────────────────
            Section("Claude (Anthropic direct)") {
                SecureField("API klíč", text: $anthropicKey)
                    .onSubmit { saveKey(anthropicKey, for: .anthropic) }
                saveButton(for: .anthropic, key: anthropicKey)
                fetchModelsRow(for: .anthropic)
            }

            // ── ChatGPT (Azure) slot 1 ─────────────────────────────────────
            Section("ChatGPT (Azure) – slot 1") {
                Text("Zadej celou URL deployment (vč. /openai/deployments/…), nebo jen resource URL + deployment name zvlášť.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API klíč", text: $azureKey)
                    .onSubmit { saveKey(azureKey, for: .azureOpenai) }
                TextField("Deployment URL", text: Binding(
                    get: { config.azureEndpoint ?? "" },
                    set: {
                        config.azureEndpoint = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureEndpoint = config.azureEndpoint }
                    }
                ))
                TextField("Deployment name (jen při resource URL výše)", text: Binding(
                    get: { config.azureDeploymentName ?? "" },
                    set: {
                        config.azureDeploymentName = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureDeploymentName = config.azureDeploymentName }
                    }
                ))
                TextField("API verze (výchozí: \(AppConfig.defaultAzureAPIVersion))", text: Binding(
                    get: { config.azureAPIVersion ?? "" },
                    set: {
                        config.azureAPIVersion = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAPIVersion = config.azureAPIVersion }
                    }
                ))
                saveButton(for: .azureOpenai, key: azureKey)
            }

            // ── ChatGPT (Azure) slot 2 ─────────────────────────────────────
            Section("ChatGPT (Azure) – slot 2") {
                SecureField("API klíč", text: $azureKey2)
                    .onSubmit { saveKey(azureKey2, for: .azureOpenai2) }
                TextField("Deployment URL", text: Binding(
                    get: { config.azureEndpoint2 ?? "" },
                    set: {
                        config.azureEndpoint2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureEndpoint2 = config.azureEndpoint2 }
                    }
                ))
                TextField("Deployment name (jen při resource URL výše)", text: Binding(
                    get: { config.azureDeploymentName2 ?? "" },
                    set: {
                        config.azureDeploymentName2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureDeploymentName2 = config.azureDeploymentName2 }
                    }
                ))
                TextField("API verze (výchozí: \(AppConfig.defaultAzureAPIVersion))", text: Binding(
                    get: { config.azureAPIVersion2 ?? "" },
                    set: {
                        config.azureAPIVersion2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAPIVersion2 = config.azureAPIVersion2 }
                    }
                ))
                saveButton(for: .azureOpenai2, key: azureKey2)
            }

            // ── OpenAI direct ──────────────────────────────────────────────
            Section("OpenAI (direct)") {
                SecureField("API klíč", text: $openaiKey)
                    .onSubmit { saveKey(openaiKey, for: .openai) }
                saveButton(for: .openai, key: openaiKey)
                fetchModelsRow(for: .openai)
            }

            // ── Custom OpenAI-compatible ───────────────────────────────────
            Section("Vlastní OpenAI-compatible") {
                TextField("Base URL (např. http://localhost:11434/v1)", text: Binding(
                    get: { config.customOpenAIBaseURL ?? "" },
                    set: {
                        config.customOpenAIBaseURL = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIBaseURL = config.customOpenAIBaseURL }
                    }
                ))
                SecureField("API klíč (volitelné)", text: $customKey)
                    .onSubmit { saveKey(customKey, for: .customOpenAI) }
                saveButton(for: .customOpenAI, key: customKey)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fetchModelsRow(for provider: ProviderType) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await fetchModels(for: provider) }
            } label: {
                if isFetching == provider {
                    HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Načítám modely…") }
                } else {
                    Label("Aktualizovat modely", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetching != nil)
            if let stored = config.modelPresets[provider.rawValue] {
                Text("\(stored.count) modelů uloženo").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let error = fetchError[provider] {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func fetchModels(for provider: ProviderType) async {
        isFetching = provider
        fetchError[provider] = nil
        do {
            let models = try await ModelFetcher.fetch(for: provider)
            reviewModels = models
            reviewingProvider = provider
        } catch {
            fetchError[provider] = error.localizedDescription
        }
        isFetching = nil
    }

    private func saveButton(for provider: ProviderType, key: String) -> some View {
        HStack {
            Button("Uložit") { saveKey(key, for: provider) }.disabled(key.isEmpty)
            if let saved = keySaveStatus[provider] {
                Image(systemName: saved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(saved ? .green : .red)
            }
        }
    }

    private func saveKey(_ key: String, for provider: ProviderType) {
        do {
            try KeychainStore.save(apiKey: key, for: provider)
            keySaveStatus[provider] = true
        } catch {
            keySaveStatus[provider] = false
        }
    }

    private func loadKeys() {
        azureAnthropicKey = (try? KeychainStore.load(for: .azureAnthropic)) ?? ""
        anthropicKey      = (try? KeychainStore.load(for: .anthropic))      ?? ""
        openaiKey         = (try? KeychainStore.load(for: .openai))         ?? ""
        azureKey          = (try? KeychainStore.load(for: .azureOpenai))    ?? ""
        azureKey2         = (try? KeychainStore.load(for: .azureOpenai2))   ?? ""
        customKey         = (try? KeychainStore.load(for: .customOpenAI))   ?? ""
    }
}

// MARK: - Model Review Sheet

private struct ModelReviewSheet: View {
    let provider: ProviderType
    @Binding var models: [FetchedModel]
    let onSave: ([FetchedModel]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Modely – \(provider.displayName)").font(.headline); Spacer() }.padding()
            Divider()
            List($models) { $model in
                HStack(spacing: 10) {
                    Toggle("", isOn: $model.isIncluded).labelsHidden()
                        .onChange(of: model.isIncluded) { _, included in
                            if !included && model.isRecommended { model.isRecommended = false }
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName)
                            .strikethrough(!model.isIncluded, color: .secondary)
                            .foregroundStyle(model.isIncluded ? .primary : .secondary)
                        if model.inUseByAction {
                            Text("Používáno v akci").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button {
                        let t = model.id; for i in models.indices { models[i].isRecommended = models[i].id == t }
                    } label: {
                        Image(systemName: model.isRecommended ? "star.fill" : "star")
                            .foregroundStyle(model.isRecommended ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain).disabled(!model.isIncluded)
                    .help("Označit jako doporučený model")
                }
            }
            Divider()
            HStack {
                Button("Zrušit", role: .cancel) { onCancel() }
                Spacer()
                Text("\(models.filter(\.isIncluded).count) z \(models.count) modelů").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Uložit") { onSave(models) }.buttonStyle(.borderedProminent)
                    .disabled(models.filter(\.isIncluded).isEmpty)
            }.padding()
        }
        .frame(width: 500, height: 440)
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    @Binding var action: Action
    var onDelete: () -> Void
    @State private var pickerModel: String = ""
    @State private var customModelText: String = ""
    @State private var confirmDelete = false
    private let customSentinel = "__custom__"
    private var isCustom: Bool { pickerModel == customSentinel }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $action.enabled).labelsHidden()
                TextField("Název akce", text: $action.name).font(.headline)
                Spacer()
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Smazat akci \"\(action.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Smazat", role: .destructive) { onDelete() }
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
        .onChange(of: action) {
            ConfigStore.shared.update { store in
                if let idx = store.actions.firstIndex(where: { $0.id == action.id }) {
                    store.actions[idx] = action
                }
            }
        }
    }

    private func syncPickerFromAction() {
        let presetIDs = action.provider.effectiveModels().map(\.id)
        if !presetIDs.isEmpty && presetIDs.contains(action.model) {
            pickerModel = action.model; customModelText = ""
        } else {
            pickerModel = customSentinel; customModelText = action.model
        }
    }

    private var providerModelRow: some View {
        HStack(spacing: 6) {
            Picker("Provider", selection: $action.provider) {
                ForEach(ProviderType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            .onChange(of: action.provider) {
                let presets = action.provider.effectiveModels()
                if presets.isEmpty { action.model = ""; pickerModel = customSentinel; customModelText = "" }
                else { let f = presets.first!.id; action.model = f; pickerModel = f; customModelText = "" }
            }

            if action.provider.effectiveModels().isEmpty {
                TextField("název modelu", text: $customModelText).frame(width: 240)
                    .onChange(of: customModelText) { if !customModelText.isEmpty { action.model = customModelText } }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(action.provider.effectiveModels()) { preset in
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

// MARK: - ProviderType extensions

extension ProviderType: Identifiable {
    public var id: String { rawValue }
}

extension ProviderType {
    var displayName: String {
        switch self {
        case .azureAnthropic: "Claude (Azure)"
        case .anthropic:      "Claude (direct)"
        case .azureOpenai:    "ChatGPT (Azure) slot 1"
        case .azureOpenai2:   "ChatGPT (Azure) slot 2"
        case .openai:         "OpenAI (direct)"
        case .customOpenAI:   "Vlastní"
        }
    }

    func effectiveModels() -> [ModelPreset] {
        let stored = ConfigStore.shared.config.modelPresets[rawValue] ?? []
        return stored.isEmpty ? presetModels : stored
    }

    var presetModels: [ModelPreset] {
        switch self {
        case .azureAnthropic, .anthropic:
            [
                .init(id: "claude-sonnet-4-6",        displayName: "claude-sonnet-4.6", isRecommended: true),
                .init(id: "claude-opus-4-7",           displayName: "claude-opus-4.7"),
                .init(id: "claude-haiku-4-5-20251001", displayName: "claude-haiku-4.5")
            ]
        case .openai:
            [
                .init(id: "gpt-4o",      displayName: "gpt-4o",      isRecommended: true),
                .init(id: "gpt-4o-mini", displayName: "gpt-4o-mini"),
                .init(id: "o4-mini",     displayName: "o4-mini"),
                .init(id: "o3",          displayName: "o3"),
                .init(id: "o3-mini",     displayName: "o3-mini"),
                .init(id: "o1",          displayName: "o1"),
                .init(id: "o1-mini",     displayName: "o1-mini")
            ]
        case .azureOpenai, .azureOpenai2, .customOpenAI:
            []
        }
    }
}
