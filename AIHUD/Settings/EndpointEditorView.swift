import AppKit
import SwiftUI

struct EndpointEditorView: View {
    @Bindable var store: EndpointStore
    let endpoint: ChatEndpoint
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var completionsURL: String
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
                        if let hint = EndpointURLWarning.hint(for: endpoint.kind, presetID: endpoint.presetID) {
                            Text(hint)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let warning = EndpointURLWarning.message(for: completionsURL) {
                            Text(warning)
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                    if isOnDevice {
                        Text("Apple Intelligence on this Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        if isChatGPT {
                            chatgptAuth
                        } else {
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
                        .disabled(isListing || isNew)
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
        .frame(width: 520, height: 560)
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
            model: endpoint.model,
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
        guard !isNew else { return }
        await store.refreshModels(for: endpoint.id)
        if let error = store.modelListErrors[endpoint.id] {
            listError = error
        } else {
            listError = nil
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
