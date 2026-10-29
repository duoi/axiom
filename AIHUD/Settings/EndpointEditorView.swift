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
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if !isOnDevice && !endpoint.urlIsFixed {
                        TextField("Base URL", text: $completionsURL, prompt: Text("https://host/v1"))
                    }
                } header: {
                    Text(isNew ? String(localized: "Add \(endpoint.name)") : endpoint.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                } footer: {
                    if !isOnDevice && !endpoint.urlIsFixed {
                        VStack(alignment: .leading, spacing: 4) {
                            if let hint = EndpointURLWarning.hint(for: endpoint.kind, presetID: endpoint.presetID) {
                                note(hint)
                            }
                            if let warning = EndpointURLWarning.message(for: completionsURL) {
                                Text(warning)
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if isOnDevice {
                    Section {
                        note(String(localized: "Apple Intelligence on this Mac."))
                    }
                } else {
                    Section {
                        if isChatGPT {
                            chatgptAuth
                        } else {
                            SecureField("API key", text: $apiKey)
                        }
                        LabeledContent {
                            Button(isListing ? String(localized: "Refreshing…") : String(localized: "Refresh")) {
                                Task { await refreshModels() }
                            }
                            .disabled(isListing || isNew)
                        } label: {
                            Text("Models")
                            if isNew {
                                Text("Save first, then refresh the list.")
                            } else if availableModels.isEmpty {
                                Text("No models listed yet.")
                            } else {
                                Text("\(availableModels.count) available")
                            }
                        }
                    } header: {
                        Text(isChatGPT ? String(localized: "ChatGPT account") : String(localized: "Authentication"))
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if isChatGPT {
                                note(String(localized: "Sign in with a ChatGPT subscription. The token stays in the Keychain."))
                            } else {
                                note(endpoint.kind == .anthropic
                                     ? String(localized: "Sent with the Anthropic Messages API. Stored in the Keychain.")
                                     : String(localized: "Sent with the OpenAI Chat Completions API. Stored in the Keychain."))
                            }
                            if let listError, !listError.isEmpty {
                                Text(listError)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    Section {
                        TextEditor(text: $systemPrompt)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 90)
                        DisclosureGroup("Default prompt") {
                            Text(store.defaultSystemPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } header: {
                        Text("System prompt")
                    } footer: {
                        note(String(localized: "Leave blank to use the default prompt. %datetime% becomes the local date and time when you send."))
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if !isOnDevice && !isNew {
                    Button("Delete", role: .destructive) {
                        store.deleteEndpoint(endpoint.id)
                        dismiss()
                    }
                }
                if let saveError, !saveError.isEmpty {
                    Text(saveError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !isOnDevice {
                    Button(isNew ? String(localized: "Add") : String(localized: "Save")) {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, HUDMetrics.inset)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 470)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var chatgptAuth: some View {
        LabeledContent {
            if chatgptConnected {
                Button("Disconnect") {
                    store.clearChatSecret(id: endpoint.id)
                }
            } else {
                Button(isConnecting
                       ? String(localized: "Connecting…")
                       : String(localized: "Connect")) {
                    Task { await connectChatGPT() }
                }
                .disabled(isConnecting)
            }
        } label: {
            Label(
                chatgptConnected ? String(localized: "Connected") : String(localized: "Not connected"),
                systemImage: chatgptConnected ? "checkmark.circle.fill" : "circle.dashed"
            )
        }
        if !chatgptConnected {
            LabeledContent {
                Button("Finish") {
                    Task { await finishPastedURL() }
                }
                .disabled(pasteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } label: {
                TextField("Redirect URL", text: $pasteURL, prompt: Text("Or paste the redirect URL"))
                    .labelsHidden()
            }
        }
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
            saveError = String(localized: "Could not listen for ChatGPT sign-in. Paste the redirect URL.")
        } catch let error as ChatGPTAuthError {
            if case .message(let message) = error {
                saveError = message
            }
        } catch {
            saveError = String(localized: "Could not connect ChatGPT subscription.")
        }
        callbackServer = nil
    }

    private func finishPastedURL() async {
        guard let session = connectSession else {
            saveError = String(localized: "Press Connect first, then paste the redirect URL.")
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
            saveError = String(localized: "Could not connect ChatGPT subscription.")
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
