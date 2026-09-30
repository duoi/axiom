import AppKit
import KeyboardShortcuts
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
        case .general: "General"
        case .appearance: "Appearance"
        case .chat: "Models"
        case .history: "History"
        case .about: "About"
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
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .chat: "text.bubble"
        case .history: "clock"
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
    @State private var historySelection: HistoryEntry.ID?
    @State private var historyDetail: HistoryEntry?
    @State private var permissionRefresh = 0

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
                case .history:
                    historyPane
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
                Text("Permissions")
                    .font(.headline)
                ForEach(SettingsPermissionRows.make(model: model)) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(row.buttonTitle) {
                            row.prompt()
                            permissionRefresh += 1
                        }
                        .disabled(row.isGranted)
                    }
                }
                Text("Ask macOS for access from here. If you already denied a prompt, the button opens System Settings. Window capture needs Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .id(permissionRefresh)
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
                                Text("Chat")
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
                }
                .frame(minHeight: 280)
                .contextMenu(forSelectionType: ChatEndpoint.ID.self) { ids in
                    if let id = ids.first, let endpoint = store.endpoints.first(where: { $0.id == id }) {
                        if EndpointTablePolicy.allowsEdit(id) {
                            Button("Edit") { presentEditor(endpoint) }
                        }
                        if !ChatEndpointCatalog.isOnDevice(endpoint) {
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
                    .disabled(selectedRow == nil || selectedRow.map { ChatEndpointCatalog.isOnDevice($0) } == true)
                    Button("Delete", role: .destructive) {
                        if let id = endpointSelection {
                            store.deleteEndpoint(id)
                            endpointSelection = store.defaultEndpointID
                        }
                    }
                    .disabled(selectedRow.map(ChatEndpointCatalog.isOnDevice) ?? store.endpoints.isEmpty)
                    Spacer()
                }
                Text("Click a row to select it. Edit opens the details. On-device cannot be edited or deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                ModelRoleSection(
                    title: "Chat model",
                    detail: "Used for text sends.",
                    store: store,
                    providerID: Binding(
                        get: { store.defaultEndpointID },
                        set: { id in
                            if let id { store.setDefault(id) }
                        }
                    ),
                    modelID: Binding(
                        get: { store.chatModelID },
                        set: { store.chatModelID = $0; store.save() }
                    ),
                    allowsUnset: false
                )
            }
            SettingsCard {
                ModelRoleSection(
                    title: "Vision model",
                    detail: "Used when a send includes an image. Leave unset to use the chat model.",
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
            }
            SettingsCard {
                Text("Reasoning effort")
                    .font(.headline)
                Picker("Reasoning effort", selection: $store.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .labelsHidden()
                Text("OpenAI-compatible sends reasoning_effort (none, minimal, low, medium, high). ChatGPT Responses sends reasoning.effort the same way. Anthropic enables thinking.budget_tokens only when effort is not None. Default is Medium.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                Text("Request timeout")
                    .font(.headline)
                HStack {
                    TextField(
                        "Seconds",
                        value: $store.requestTimeoutSeconds,
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("\(Int(ChatTimeoutSettings.minimumSeconds)) to \(Int(ChatTimeoutSettings.maximumSeconds)) seconds. Default \(Int(ChatTimeoutSettings.defaultSeconds)).")
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
                    if let existing = selectedRow ?? store.selectedEndpoint ?? store.endpoints.first,
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

    private var historyPane: some View {
        settingsPane {
            SettingsCard {
                Toggle("Save chat history", isOn: $store.savesHistory)
                Text("When on, completed chats are stored on this Mac. Nothing is uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Also save screenshots", isOn: $store.savesHistoryScreenshots)
                    .disabled(!store.savesHistory)
                Text("Stores the Screen/Window JPEG with that chat. Off by default. Does not save your original files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                Table(store.historyStore.entries, selection: $historySelection) {
                    TableColumn("Time") { entry in
                        Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 140)
                    TableColumn("Title") { entry in
                        Text(entry.title.isEmpty ? "—" : entry.title)
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                historyDetail = entry
                            }
                    }
                }
                .frame(minHeight: 240)
                .contextMenu(forSelectionType: HistoryEntry.ID.self) { ids in
                    if let id = ids.first {
                        Button("Open") {
                            historyDetail = store.historyStore.entries.first { $0.id == id }
                        }
                        Button("Delete", role: .destructive) {
                            store.historyStore.delete(id: id)
                            if historySelection == id {
                                historySelection = nil
                            }
                            if historyDetail?.id == id {
                                historyDetail = nil
                            }
                        }
                    }
                }
                HStack {
                    Button("Open") {
                        if let id = historySelection {
                            historyDetail = store.historyStore.entries.first { $0.id == id }
                        }
                    }
                    .disabled(historySelection == nil)
                    Button("Delete", role: .destructive) {
                        if let id = historySelection {
                            store.historyStore.delete(id: id)
                            historySelection = nil
                            if historyDetail?.id == id {
                                historyDetail = nil
                            }
                        }
                    }
                    .disabled(historySelection == nil)
                    Spacer()
                }
                Text("One row is one conversation. Double-click to read the full thread. Delete removes that chat and its stored screenshot. Your original files are not touched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            store.historyStore.reload()
        }
        .sheet(item: $historyDetail) { entry in
            HistoryDetailView(entry: entry, store: store.historyStore)
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
                Text("Axiom")
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
