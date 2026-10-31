import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case chat
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .chat: String(localized: "Models")
        case .history: String(localized: "History")
        case .about: String(localized: "About")
        }
    }

    static func launchPage(from arguments: [String] = CommandLine.arguments) -> SettingsPage {
        if let paired = arguments.first(where: { $0.hasPrefix("--settings-page=") }) {
            let raw = String(paired.dropFirst("--settings-page=".count))
            if raw == "vision" || raw == "models" { return .chat }
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
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .chat: "text.bubble.fill"
        case .history: "clock.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .chat: .purple
        case .history: .orange
        case .about: .gray
        }
    }
}

struct SettingsView: View {
    @Bindable var store: EndpointStore
    @Bindable var model: HUDModel
    @State private var page: SettingsPage
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var editingEndpoint: ChatEndpoint?
    @State private var choosingProvider = false
    @State private var pendingAdd: EndpointAddChoice?
    @State private var historyDetail: HistoryEntry?
    @State private var permissionRefresh = 0
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    init(store: EndpointStore, model: HUDModel, page: SettingsPage = .launchPage()) {
        self.store = store
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label {
                    Text(item.title)
                } icon: {
                    SettingsIcon(symbol: item.symbolName, tint: item.tint)
                }
                .tag(item)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(HUDMetrics.sidebarWidth)
        } detail: {
            Group {
                switch page {
                case .general:
                    generalPane
                case .appearance:
                    appearancePane
                case .chat:
                    chatPane
                case .history:
                    historyPane
                case .about:
                    aboutPane
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page.title)
        }
        // Settings keeps its sidebar, like System Settings.
        .onChange(of: columns) { columns = .all }
        .frame(minWidth: HUDMetrics.settingsSize.width, minHeight: HUDMetrics.settingsSize.height)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }

    private var generalPane: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setOpensAtLogin
                )) {
                    Text("Open at login")
                    Text("Starts Axiom in the menu bar when you log in.")
                }
                // It can change in System Settings → Login Items; coming back from there reactivates Axiom.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    loginStatus = SMAppService.mainApp.status
                }
                if loginStatus == .requiresApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError {
                    note(loginError)
                }
                Toggle(isOn: $store.keepHovering) {
                    Text("Keep the card up")
                    Text("A click outside leaves it up. Escape or the hotkey still hides it.")
                }
                Toggle(isOn: $store.usesMultilinePrompt) {
                    Text("Multiline prompt")
                    Text("Wraps up to 10 lines. Option-Return or Shift-Return starts a new line.")
                }
            }
            Section("Voice") {
                Toggle(isOn: Binding(
                    get: { store.wakeOnAxiom },
                    set: { model.onSetWake($0) }
                )) {
                    Text("Wake on Axiom")
                    Text("Say \"Axiom\" or \"Hey Axiom\" to show the card with the rest of the sentence.")
                }
                Toggle(isOn: $store.pauseToSend) {
                    Text("Pause to send")
                    Text("About 2 seconds of silence sends the prompt.")
                }
                if let status = model.voiceStatus, !status.isEmpty {
                    note(status)
                }
            }
            Section {
                ForEach(SettingsPermissionRows.make(model: model)) { row in
                    LabeledContent {
                        if row.isGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Button(row.buttonTitle) {
                                row.prompt()
                                permissionRefresh += 1
                            }
                        }
                    } label: {
                        Text(row.title)
                        if !row.isGranted {
                            Text(row.status)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                note(String(localized: "If you already denied access, the button opens System Settings."))
            }
            .id(permissionRefresh)
            Section("Shortcuts") {
                shortcutRow(String(localized: "Show and hide"), .toggleHUD)
                shortcutRow(String(localized: "Hide"), .hideCard)
                shortcutRow(String(localized: "Send"), .send)
                shortcutRow(String(localized: "New line"), .newline)
                shortcutRow(String(localized: "New line"), .newlineShift)
                shortcutRow(String(localized: "Ask and Agent"), .cyclePreset)
                shortcutRow(String(localized: "Capture"), .cycleCapture)
                shortcutRow(String(localized: "Add context"), .addContext)
                shortcutRow(String(localized: "Recording"), .toggleIncognito)
                shortcutRow(String(localized: "Dictation"), .toggleDictation)
            }
        }
    }

    private func shortcutRow(_ title: String, _ name: KeyboardShortcuts.Name) -> some View {
        LabeledContent(title) {
            KeyboardShortcuts.Recorder(for: name)
                .fixedSize()
        }
    }

    private var experimentalBinding: Binding<Bool> {
        Binding(
            get: { store.experimentalAgent },
            set: { on in
                store.experimentalAgent = on
                model.applyModelPreset()
            }
        )
    }

    private func agentBinding(_ row: ChatEndpoint) -> Binding<Bool> {
        Binding(
            get: { store.endpoints.first { $0.id == row.id }?.prefersAgent ?? false },
            set: { on in
                store.setAgentMode(id: row.id, on: on)
                if row.id == store.defaultEndpointID {
                    model.applyModelPreset()
                }
            }
        )
    }

    private func chooseAgentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.saveAgentFolder(url)
    }

    private var appearancePane: some View {
        Form {
            Section {
                Picker("Finish", selection: $store.usesMatte) {
                    Text("Glass").tag(false)
                    Text("Matte").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    HStack {
                        Slider(value: $store.glassPercent, in: 0...100)
                        Text("\(Int(store.glassPercent.rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                } label: {
                    Text("Glass amount")
                    Text("100% is clear. Lower values tint the card.")
                }
            } footer: {
                note(String(localized: "Glass is clear. Matte is the heavier glass."))
            }
            Section {
                Toggle(isOn: $store.usesNewUI) {
                    Text("New UI")
                    Text("The prompt sits in its own capsule, with the buttons floating under it.")
                }
            }
        }
    }

    private var chatPane: some View {
        Form {
            Section {
                ForEach(store.endpoints) { endpoint in
                    providerRow(endpoint)
                }
                HStack {
                    Spacer()
                    // A Menu in a grouped form row ignored real clicks, so this is a plain button and a popover.
                    Button("Add Provider…") { choosingProvider = true }
                        .popover(isPresented: $choosingProvider, arrowEdge: .bottom) {
                            addProviderList
                        }
                }
            } header: {
                Text("Providers")
            } footer: {
                if store.experimentalAgent {
                    note(String(localized: "Turn on Agent to show Ask and Agent on the card and let that provider use tools. On-device cannot use tools."))
                }
            }
            Section("Chat") {
                ModelRoleSection(
                    store: store,
                    providerID: Binding(
                        get: { store.defaultEndpointID },
                        set: { id in
                            if let id {
                                store.setDefault(id)
                                model.applyModelPreset()
                            }
                        }
                    ),
                    modelID: Binding(
                        get: { store.chatModelID },
                        set: { store.chatModelID = $0; store.save() }
                    ),
                    allowsUnset: false
                )
                Picker(selection: $store.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                } label: {
                    Text("Reasoning effort")
                    Text("Anthropic thinks unless this is None.")
                }
            }
            Section {
                ModelRoleSection(
                    store: store,
                    providerID: Binding(
                        get: { store.visionEndpointID },
                        set: { id in
                            if let id {
                                store.setVision(id)
                            } else {
                                store.clearVisionSelection()
                            }
                        }
                    ),
                    modelID: Binding(
                        get: { store.visionModelID },
                        set: { store.visionModelID = $0; store.save() }
                    ),
                    allowsUnset: true
                )
            } header: {
                Text("Vision")
            } footer: {
                note(String(localized: "Used for prompts that include an image."))
            }
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(
                            "Request timeout",
                            value: $store.requestTimeoutSeconds,
                            format: .number.precision(.fractionLength(0))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Request timeout")
                    Text("\(Int(ChatTimeoutSettings.minimumSeconds)) to \(Int(ChatTimeoutSettings.maximumSeconds)) seconds. Default is \(Int(ChatTimeoutSettings.defaultSeconds)).")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default prompt")
                    note(String(localized: "Used when a provider leaves its own prompt blank. %datetime% becomes the local date and time."))
                    TextEditor(text: $store.defaultSystemPrompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                }
            }
            Section {
                Toggle(isOn: experimentalBinding) {
                    Text("Experimental")
                    Text("Adds an Agent switch to each provider. Agent lets a cloud model use tools.")
                }
                if store.experimentalAgent {
                    LabeledContent {
                        HStack {
                            if store.agentFolderPath != nil {
                                Button("Clear") { store.clearAgentFolder() }
                            }
                            Button("Choose…") { chooseAgentFolder() }
                        }
                    } label: {
                        Text("Agent folder")
                        Text(store.agentFolderPath ?? String(localized: "No folder selected"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } footer: {
                if store.experimentalAgent {
                    note(String(localized: "Agent can list, search, and read files in this folder, and stays inside it."))
                }
            }
        }
        .onAppear {
            if editingEndpoint == nil {
                if let preset = SettingsPage.editPreset(),
                   let match = store.endpoints.first(where: { $0.presetID == preset })
                {
                    editingEndpoint = match
                } else if CommandLine.arguments.contains("--edit-endpoint") {
                    if let existing = store.selectedEndpoint ?? store.endpoints.first,
                       EndpointTablePolicy.allowsEdit(existing.id)
                    {
                        editingEndpoint = existing
                    }
                }
            }
        }
        .sheet(item: $editingEndpoint) { endpoint in
            EndpointEditorView(store: store, endpoint: endpoint)
        }
    }

    private var addProviderList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                addProviderButton(String(localized: "Custom…"), .custom)
                Divider().padding(.vertical, 4).padding(.horizontal, 8)
                ForEach(ChatEndpointCatalog.cloudPresets, id: \.id) { preset in
                    addProviderButton(preset.name, .preset(preset.id))
                }
            }
            .padding(6)
        }
        .frame(width: 260, height: 380)
        // The editor sheet opens once the popover is gone; presenting both at once drops the sheet.
        .onDisappear {
            if let choice = pendingAdd {
                pendingAdd = nil
                beginDraft(choice)
            }
        }
    }

    private func addProviderButton(_ title: String, _ choice: EndpointAddChoice) -> some View {
        AddProviderRow(title: title) {
            pendingAdd = choice
            choosingProvider = false
        }
    }

    private func providerRow(_ endpoint: ChatEndpoint) -> some View {
        let onDevice = ChatEndpointCatalog.isOnDevice(endpoint)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(endpoint.name)
                    if endpoint.id == store.defaultEndpointID {
                        roleBadge(String(localized: "Chat"))
                    }
                    if endpoint.id == store.visionEndpointID {
                        roleBadge(String(localized: "Vision"))
                    }
                }
                Text(endpoint.hostLabel.isEmpty ? "—" : endpoint.hostLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.experimentalAgent, !onDevice {
                Toggle("Agent", isOn: agentBinding(endpoint))
                    .toggleStyle(.checkbox)
            }
            if EndpointTablePolicy.allowsEdit(endpoint.id) {
                Button("Edit…") { presentEditor(endpoint) }
            }
        }
        .contextMenu {
            if EndpointTablePolicy.allowsEdit(endpoint.id) {
                Button("Edit…") { presentEditor(endpoint) }
            }
            if !onDevice {
                Button("Delete", role: .destructive) { store.deleteEndpoint(endpoint.id) }
            }
        }
    }

    private func roleBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    private var historyPane: some View {
        Form {
            Section {
                Toggle(isOn: $store.savesHistory) {
                    Text("Save chat history")
                    Text("Finished chats are saved on this Mac. Nothing is uploaded.")
                }
                Toggle(isOn: $store.savesHistoryScreenshots) {
                    Text("Also save screenshots")
                    Text("Keeps the Screen or Window capture with its chat. Turning this off deletes saved screenshots.")
                }
                .disabled(!store.savesHistory)
            }
            Section {
                if store.historyStore.entries.isEmpty {
                    note(String(localized: "No saved chats."))
                }
                ForEach(store.historyStore.entries) { entry in
                    Button {
                        historyDetail = entry
                    } label: {
                        LabeledContent {
                            Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                        } label: {
                            Text(entry.title.isEmpty ? "—" : entry.title)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open") { historyDetail = entry }
                        Button("Delete", role: .destructive) {
                            store.historyStore.delete(id: entry.id)
                            if historyDetail?.id == entry.id {
                                historyDetail = nil
                            }
                        }
                    }
                }
            } header: {
                Text("Chats")
            } footer: {
                note(String(localized: "Click a chat to open it. Control-click to delete it and its screenshot."))
            }
        }
        .onAppear {
            store.historyStore.reload()
        }
        .sheet(item: $historyDetail) { entry in
            HistoryDetailView(entry: entry, store: store.historyStore)
        }
    }

    private func beginDraft(_ choice: EndpointAddChoice) {
        editingEndpoint = store.draftEndpoint(for: choice)
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
        VStack(spacing: 8) {
            AxiomLogo()
                .frame(width: 88, height: 64)
            Text("Axiom")
                .font(.title2.weight(.semibold))
            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)
            Spacer().frame(height: 8)
            Text("Steven Johns")
            Link("github.com/duoi/axiom", destination: URL(string: "https://github.com/duoi/axiom")!)
            Text("MIT License")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle(isOn: $store.debugToolsEnabled) {
                Text("Debug tools")
                Text("Adds Debug to the menu bar and the card menu: card states, glow, and a live HTTP transcript.")
            }
            .toggleStyle(.switch)
            .frame(maxWidth: 400)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// A white symbol on a colored tile, like the System Settings sidebar.
private struct SettingsIcon: View {
    var symbol: String
    var tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// One choice in the Add Provider popover, highlighted on hover like a menu item.
private struct AddProviderRow: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
