import AppKit
import KeyboardShortcuts
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case chat
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .chat: "Chat"
        case .about: "About"
        }
    }

    static func launchPage(from arguments: [String] = CommandLine.arguments) -> SettingsPage {
        if let paired = arguments.first(where: { $0.hasPrefix("--settings-page=") }) {
            let raw = String(paired.dropFirst("--settings-page=".count))
            if raw == "vision" { return .chat }
            return SettingsPage(rawValue: raw) ?? .general
        }
        return .general
    }

    static func editPreset(from arguments: [String] = CommandLine.arguments) -> String? {
        guard let paired = arguments.first(where: { $0.hasPrefix("--edit-preset=") }) else {
            return nil
        }
        let value = String(paired.dropFirst("--edit-preset=".count))
        return value.isEmpty ? nil : value
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .chat: "text.bubble"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var store: EndpointStore
    @Bindable var model: HUDModel
    @State private var page: SettingsPage = SettingsPage.launchPage()
    @State private var endpointSelection: ChatEndpoint.ID?
    @State private var editingEndpoint: ChatEndpoint?

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: HUDMetrics.sidebarWidth)
            .padding(.top, HUDMetrics.inset)

            Divider()

            Group {
                switch page {
                case .general:
                    generalPane
                case .appearance:
                    appearancePane
                case .chat:
                    chatPane
                case .about:
                    aboutPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: HUDMetrics.settingsSize.width, minHeight: HUDMetrics.settingsSize.height - 40)
    }

    private var generalPane: some View {
        settingsPane {
            SettingsCard {
                Toggle("Keep the card up", isOn: $store.keepHovering)
                Text("When this is on, clicking another window leaves the card in place. Escape or the hotkey still dismisses it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Multiline prompt", isOn: $store.usesMultilinePrompt)
                Text("Wrap the prompt and grow the card up to 10 lines. Return still sends. Option-Return inserts a line break.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Wake on Axiom", isOn: Binding(
                    get: { store.wakeOnAxiom },
                    set: { model.onSetWake($0) }
                ))
                Text("Listen for Axiom and show the card. Permission is requested here, not from the card.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Pause to send", isOn: $store.pauseToSend)
                Text("About 2 seconds of silence after a non-empty draft sends. Return still sends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let status = model.voiceStatus, !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(VoiceStatusCopy.adHocPermission)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                KeyboardShortcuts.Recorder("Hotkey", name: .toggleHUD)
            }
        }
    }

    private var appearancePane: some View {
        settingsPane {
            SettingsCard {
                Picker("Finish", selection: $store.usesMatte) {
                    Text("Glass").tag(false)
                    Text("Matte").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Glass is the clear card. Matte is the heavier glass. Neither is a solid fill.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                Text("Glass amount")
                Slider(value: $store.glassPercent, in: 0...100)
                Text("\(Int(store.glassPercent.rounded()))%")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("100% leaves the glass clear. Lower values add a quiet veil.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chatPane: some View {
        settingsPane {
            SettingsCard {
                Table(store.endpoints, selection: $endpointSelection) {
                    TableColumn("Name") { endpoint in
                        HStack(spacing: 6) {
                            if endpoint.id == store.defaultEndpointID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            Text(endpoint.name)
                            if endpoint.id == store.defaultEndpointID {
                                Text("Default")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if endpoint.id == store.visionEndpointID {
                                Text("Vision")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn("Host") { endpoint in
                        Text(endpoint.hostLabel.isEmpty ? "—" : endpoint.hostLabel)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Model") { endpoint in
                        let label = endpoint.modelLabel
                        Text(label.isEmpty ? "—" : label)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 280)
                .contextMenu(forSelectionType: ChatEndpoint.ID.self) { ids in
                    if let id = ids.first, let endpoint = store.endpoints.first(where: { $0.id == id }) {
                        Button("Edit") { presentEditor(endpoint) }
                        Button("Make default") { store.setDefault(id) }
                        if !ChatEndpointCatalog.isOnDevice(endpoint) {
                            Button("Set as vision model") { store.setVision(id) }
                            Button("Delete", role: .destructive) { store.deleteEndpoint(id) }
                        }
                    }
                }
                HStack {
                    Menu("Add") {
                        Button("Custom") {
                            beginDraft(.custom)
                        }
                        Divider()
                        ForEach(ChatEndpointCatalog.cloudPresets, id: \.id) { preset in
                            Button(preset.name) {
                                beginDraft(.preset(preset.id))
                            }
                        }
                    }
                    Button("Edit") {
                        if let row = selectedRow {
                            presentEditor(row)
                        }
                    }
                    .disabled(selectedRow == nil)
                    Button("Make default") {
                        if let id = selectedRow?.id {
                            store.setDefault(id)
                        }
                    }
                    .disabled(selectedRow == nil || selectedRow?.id == store.defaultEndpointID)
                    Button("Set as vision model") {
                        if let id = selectedRow?.id {
                            store.setVision(id)
                        }
                    }
                    .disabled(selectedRow.map(ChatEndpointCatalog.isOnDevice) ?? true)
                    Button("Delete", role: .destructive) {
                        if let id = endpointSelection {
                            store.deleteEndpoint(id)
                            endpointSelection = store.defaultEndpointID
                        }
                    }
                    .disabled(selectedRow.map(ChatEndpointCatalog.isOnDevice) ?? store.endpoints.isEmpty)
                    Spacer()
                }
                Text("Click a row to select it. Edit opens the details. Make default sets the chat endpoint. Set as vision model marks the row used for images. On-device cannot be deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                Text("Default prompt")
                    .font(.headline)
                Text("Used when an endpoint leaves its system prompt blank. %datetime% is replaced with the current local date and time when you send.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $store.defaultSystemPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .onAppear {
            if endpointSelection == nil {
                endpointSelection = store.defaultEndpointID
            }
            if editingEndpoint == nil {
                if let preset = SettingsPage.editPreset(),
                   let match = store.endpoints.first(where: { $0.presetID == preset })
                {
                    endpointSelection = match.id
                    editingEndpoint = match
                } else if CommandLine.arguments.contains("--edit-endpoint") {
                    if let existing = selectedRow ?? store.selectedEndpoint ?? store.endpoints.first {
                        editingEndpoint = existing
                    }
                }
            }
        }
        .sheet(item: $editingEndpoint) { endpoint in
            EndpointEditorView(store: store, endpoint: endpoint)
        }
    }

    private var selectedRow: ChatEndpoint? {
        if let endpointSelection {
            return store.endpoints.first(where: { $0.id == endpointSelection })
                ?? (editingEndpoint?.id == endpointSelection ? editingEndpoint : nil)
        }
        return store.selectedEndpoint
    }

    private func beginDraft(_ choice: EndpointAddChoice) {
        let created = store.draftEndpoint(for: choice)
        endpointSelection = created.id
        editingEndpoint = created
    }

    private func presentEditor(_ endpoint: ChatEndpoint) {
        let next = EndpointTablePolicy.apply(
            .edit(endpoint.id),
            defaultID: store.defaultEndpointID,
            visionID: store.visionEndpointID
        )
        guard let editorID = next.opensEditor else { return }
        if let existing = store.endpoints.first(where: { $0.id == editorID }) {
            editingEndpoint = existing
        } else if endpoint.id == editorID {
            editingEndpoint = endpoint
        }
    }

    private var aboutPane: some View {
        settingsPane {
            VStack(spacing: HUDMetrics.controlSpacing) {
                AxiomLogo()
                    .frame(width: 88, height: 64)
                Text("AI HUD")
                    .font(.title2.weight(.semibold))
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
                Text("Steven Johns")
                Link("github.com/duoi/axiom", destination: URL(string: "https://github.com/duoi/axiom")!)
                Text("MIT License")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func settingsPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                content()
            }
            .padding(HUDMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct EndpointEditorView: View {
    @Bindable var store: EndpointStore
    let endpoint: ChatEndpoint
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var completionsURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var systemPrompt: String
    @State private var saveError: String?
    @State private var listError: String?
    @State private var isListing = false
    @State private var isConnecting = false
    @State private var pasteURL = ""
    @State private var connectSession: ChatGPTAuth.ConnectSession?
    @State private var callbackServer: OAuthCallbackServer?

    init(store: EndpointStore, endpoint: ChatEndpoint) {
        self.store = store
        self.endpoint = endpoint
        _name = State(initialValue: endpoint.name)
        _completionsURL = State(initialValue: endpoint.completionsURL)
        _model = State(initialValue: endpoint.model)
        _apiKey = State(initialValue: endpoint.usesChatGPTAuth ? "" : store.apiKey(for: endpoint.id))
        _systemPrompt = State(initialValue: endpoint.systemPrompt)
        _listError = State(initialValue: store.modelListErrors[endpoint.id])
    }

    private var isOnDevice: Bool {
        ChatEndpointCatalog.isOnDevice(endpoint)
    }

    private var isChatGPT: Bool {
        endpoint.kind == .chatgptSubscription
    }

    private var isNew: Bool {
        !store.endpoints.contains(where: { $0.id == endpoint.id })
    }

    private var chatgptConnected: Bool {
        ChatGPTAuth.parse(store.apiKey(for: endpoint.id)) != nil
    }

    private var availableModels: [String] {
        store.endpoints.first(where: { $0.id == endpoint.id })?.availableModels ?? endpoint.availableModels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                    Text("Endpoint")
                        .font(.headline)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    if !isOnDevice && !endpoint.urlIsFixed {
                        TextField("Base URL", text: $completionsURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    if isOnDevice {
                        Text("Apple Intelligence on this Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        modelField
                        if isChatGPT {
                            chatgptAuth
                        } else if !isOnDevice {
                            SecureField("API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            Text(endpoint.kind == .anthropic
                                 ? "Anthropic Messages."
                                 : "OpenAI-compatible Chat Completions.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh") {
                            Task { await refreshModels() }
                        }
                        .disabled(isListing)
                    }
                    if let saveError, !saveError.isEmpty {
                        Text(saveError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if let listError, !listError.isEmpty {
                        Text(listError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if !isOnDevice {
                        Text("System prompt")
                            .font(.headline)
                        Text("Leave blank to use the default prompt in Settings. %datetime% is replaced with the current local date and time when you send.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Blank uses the default prompt.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $systemPrompt)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 140)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        DisclosureGroup("Default prompt") {
                            Text(store.defaultSystemPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            HStack {
                Button("Delete", role: .destructive) {
                    store.deleteEndpoint(endpoint.id)
                    dismiss()
                }
                .disabled(isOnDevice || isNew)
                Button("Make default") {
                    if isNew {
                        saveError = "Save this endpoint before making it the default."
                    } else {
                        store.setDefault(endpoint.id)
                    }
                }
                .disabled(endpoint.id == store.defaultEndpointID)
                if !isOnDevice {
                    Button("Set as vision model") {
                        if isNew {
                            saveError = "Save this endpoint before using it for vision."
                        } else {
                            store.setVision(endpoint.id)
                        }
                    }
                    .disabled(endpoint.id == store.visionEndpointID)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                if !isOnDevice {
                    Button("Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(HUDMetrics.inset)
        .frame(width: 520, height: 620)
    }

    @ViewBuilder
    private var modelField: some View {
        if availableModels.isEmpty {
            TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Model", selection: $model) {
                    ForEach(availableModels, id: \.self) { id in
                        Text(id).tag(id)
                    }
                    if !availableModels.contains(model) && !model.isEmpty {
                        Text(model).tag(model)
                    }
                }
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var chatgptAuth: some View {
        HStack {
            Text(chatgptConnected ? "Connected" : "Not connected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if chatgptConnected {
                Button("Disconnect") {
                    store.clearChatSecret(id: endpoint.id)
                }
            } else {
                Button(isConnecting ? "Connecting…" : "Connect") {
                    Task { await connectChatGPT() }
                }
                .disabled(isConnecting)
            }
        }
        if !chatgptConnected {
            TextField("Or paste the redirect URL", text: $pasteURL)
                .textFieldStyle(.roundedBorder)
            Button("Finish with pasted URL") {
                Task { await finishPastedURL() }
            }
            .disabled(pasteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Text("ChatGPT subscription uses Codex OAuth. Tokens stay in the Keychain.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func drafted() -> ChatEndpoint {
        ChatEndpoint(
            id: endpoint.id,
            name: name,
            completionsURL: endpoint.urlIsFixed ? endpoint.completionsURL : completionsURL,
            model: model,
            systemPrompt: systemPrompt,
            kind: endpoint.kind,
            presetID: endpoint.presetID,
            availableModels: availableModels
        )
    }

    private func save(listing: Bool = true) {
        let secret = isChatGPT ? store.apiKey(for: endpoint.id) : apiKey
        if let rejection = store.saveEndpoint(drafted(), apiKey: secret) {
            saveError = rejection
            return
        }
        saveError = nil
        if listing {
            Task { await refreshModels() }
        }
        dismiss()
    }

    private func refreshModels() async {
        isListing = true
        defer { isListing = false }
        if !isChatGPT, !apiKey.isEmpty {
            _ = store.saveEndpoint(drafted(), apiKey: apiKey)
        }
        let current = store.endpoints.first(where: { $0.id == endpoint.id }) ?? drafted()
        let secret = store.apiKey(for: current.id)
        let models = await ModelListClient().list(
            endpoint: current,
            secret: secret,
            allowedCleartextHosts: store.allowedCleartextHosts
        )
        if ModelList.isFailed(models: models) {
            listError = ModelList.failureMessage
            store.modelListErrors[current.id] = ModelList.failureMessage
            return
        }
        listError = nil
        store.applyListedModels(models, to: current.id)
        if let updated = store.endpoints.first(where: { $0.id == current.id }) {
            model = updated.model
        }
    }

    private func connectChatGPT() async {
        isConnecting = true
        defer { isConnecting = false }
        let session = ChatGPTAuth.startConnect()
        connectSession = session
        NSWorkspace.shared.open(session.url)
        let server = OAuthCallbackServer()
        callbackServer = server
        do {
            let url = try await server.listen()
            try await finish(url: url, session: session)
        } catch is CancellationError {
            saveError = "Could not listen for ChatGPT sign-in. Paste the redirect URL."
        } catch let error as ChatGPTAuthError {
            if case .message(let message) = error {
                saveError = message
            }
        } catch {
            saveError = "Could not connect ChatGPT subscription."
        }
        callbackServer = nil
    }

    private func finishPastedURL() async {
        guard let session = connectSession else {
            saveError = "Press Connect first, then paste the redirect URL."
            return
        }
        do {
            let parsed = try ChatGPTAuth.parseAuthorizationInput(pasteURL)
            try ChatGPTAuth.assertState(session: session, parsedState: parsed.state)
            let credential = try await ChatGPTAuth.exchangeCode(code: parsed.code, verifier: session.verifier)
            try await storeConnected(credential)
        } catch let error as ChatGPTAuthError {
            if case .message(let message) = error {
                saveError = message
            }
        } catch {
            saveError = "Could not connect ChatGPT subscription."
        }
    }

    private func finish(url: URL, session: ChatGPTAuth.ConnectSession) async throws {
        let parsed = try ChatGPTAuth.parseAuthorizationInput(url.absoluteString)
        try ChatGPTAuth.assertState(session: session, parsedState: parsed.state)
        let credential = try await ChatGPTAuth.exchangeCode(code: parsed.code, verifier: session.verifier)
        try await storeConnected(credential)
    }

    private func storeConnected(_ credential: ChatGPTAuth.Credential) async throws {
        let secret = ChatGPTAuth.serialize(credential)
        if let rejection = store.saveEndpoint(drafted(), apiKey: secret) {
            saveError = rejection
            return
        }
        saveError = nil
        await refreshModels()
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
            content()
        }
        .padding(HUDMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
