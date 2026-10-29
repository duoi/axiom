import Foundation

struct DevEndpointFile: Codable, Equatable, Sendable {
    var model: String
    var completionsURL: String
    var apiKey: String

    var isUsable: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !completionsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.isEmpty
    }

    static func load(from url: URL) -> DevEndpointFile? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DevEndpointFile.self, from: data),
              file.isUsable
        else {
            return nil
        }
        return file
    }

    static func bundled() -> DevEndpointFile? {
        guard let url = Bundle.main.url(forResource: "dev-endpoint", withExtension: "json") else {
            return nil
        }
        return load(from: url)
    }
}

@MainActor
@Observable
final class EndpointStore {
    private static let visionModelKey = "endpoint.visionModel"
    private static let visionURLKey = "endpoint.visionURL"
    private static let hoverKey = "hud.keepHovering"
    private static let captureKey = "hud.captureTarget"
    private static let matteKey = HUDMaterial.matteKey
    private static let newUIKey = "hud.newUI"

    var endpoints: [ChatEndpoint]
    var defaultEndpointID: UUID?
    var visionEndpointID: UUID?
    var chatModelID: String
    var apiKeys: [UUID: String]
    var modelListErrors: [UUID: String]
    var visionModel: String
    var visionURL: String
    var devCleartextHost: String?
    private let defaults: UserDefaults
    private let secrets: SecretStore
    var keepHovering: Bool {
        didSet { defaults.set(keepHovering, forKey: Self.hoverKey) }
    }
    var experimentalAgent: Bool {
        didSet { ExperimentalAgent.save(experimentalAgent, to: defaults) }
    }
    var agentFolderPath: String?
    var usesMultilinePrompt: Bool {
        didSet { PromptSettings.saveMultiline(usesMultilinePrompt, to: defaults) }
    }
    var captureTarget: CaptureTarget {
        didSet { defaults.set(captureTarget.rawValue, forKey: Self.captureKey) }
    }
    var usesMatte: Bool {
        didSet {
            defaults.set(usesMatte, forKey: Self.matteKey)
            onAppearanceChange()
        }
    }
    var usesNewUI: Bool {
        didSet {
            defaults.set(usesNewUI, forKey: Self.newUIKey)
            onAppearanceChange()
        }
    }
    var glassStyle: GlassStyle {
        HUDMaterial.effectStyle(matte: usesMatte)
    }
    var glassAmount: Double {
        didSet {
            let clamped = HUDMaterial.clampAmount(glassAmount)
            if clamped != glassAmount {
                glassAmount = clamped
                return
            }
            HUDMaterial.saveAmount(clamped, to: defaults)
            onAppearanceChange()
        }
    }

    var glassPercent: Double {
        get { glassAmount * 100 }
        set { glassAmount = newValue / 100 }
    }
    var defaultSystemPrompt: String {
        didSet {
            let shown = SystemPrompt.displayed(defaultSystemPrompt)
            if shown != defaultSystemPrompt {
                defaultSystemPrompt = shown
                return
            }
            SystemPrompt.saveGlobal(shown, to: defaults)
        }
    }

    var usesOnDevice: Bool {
        ChatEndpointCatalog.usesOnDevice(endpoints: endpoints, defaultID: defaultEndpointID)
    }
    var wakeOnAxiom: Bool {
        didSet { VoiceSettings.saveWakeOnAxiom(wakeOnAxiom, to: defaults) }
    }
    var pauseToSend: Bool {
        didSet { VoiceSettings.savePauseToSend(pauseToSend, to: defaults) }
    }
    var savesHistory: Bool {
        didSet {
            HistorySettings.saveEnabled(savesHistory, to: defaults)
            if !savesHistory, savesHistoryScreenshots {
                savesHistoryScreenshots = false
            }
        }
    }
    var savesHistoryScreenshots: Bool {
        didSet {
            HistorySettings.saveSaveScreenshots(savesHistoryScreenshots, to: defaults)
            if oldValue, !savesHistoryScreenshots {
                historyStore.removeAllScreenshots()
            }
        }
    }
    var debugToolsEnabled: Bool {
        didSet {
            DebugSettings.saveEnabled(debugToolsEnabled, to: defaults)
            onDebugToolsChange(debugToolsEnabled)
        }
    }
    var onDebugToolsChange: (Bool) -> Void = { _ in }

    /// Debug shows when it is turned on in Settings, About, or for a `--debug` developer launch.
    func showsDebug(arguments: [String] = CommandLine.arguments) -> Bool {
        debugToolsEnabled || DebugRouting.enabled(by: arguments)
    }

    var reasoningEffort: ReasoningEffort {
        didSet { ReasoningEffort.save(reasoningEffort, to: defaults) }
    }
    var requestTimeoutSeconds: TimeInterval {
        didSet {
            let clamped = ChatTimeoutSettings.clamp(requestTimeoutSeconds)
            if clamped != requestTimeoutSeconds {
                requestTimeoutSeconds = clamped
                return
            }
            ChatTimeoutSettings.save(clamped, to: defaults)
        }
    }
    let historyStore: HistoryStore
    var onAppearanceChange: () -> Void = {}

    func saveAgentFolder(_ url: URL) {
        guard let data = FolderGrant.data(for: url) else { return }
        defaults.set(data, forKey: FolderGrant.defaultsKey)
        agentFolderPath = FolderGrant.displayPath(url)
    }

    func clearAgentFolder() {
        FolderGrant.clear(in: defaults)
        agentFolderPath = nil
    }

    init(
        defaults: UserDefaults = .standard,
        secrets: SecretStore = .keychain,
        historyRoot: URL = HistoryStore.defaultRoot()
    ) {
        self.defaults = defaults
        self.secrets = secrets
        let dev = DevEndpointFile.bundled()
        devCleartextHost = dev.flatMap { URL(string: $0.completionsURL)?.host }
        let loaded = ChatEndpointCatalog.load(from: defaults)
        var loadedEndpoints = ChatEndpointCatalog.ensuringCatalog(
            ChatEndpointCatalog.decodedEndpoints(from: defaults) ?? loaded.endpoints
        )
        var loadedDefault = loaded.defaultID
        var loadedVision = loaded.visionID
        let vision = ChatEndpointCatalog.migrateVision(
            endpoints: loadedEndpoints,
            visionID: loadedVision,
            legacyURL: defaults.string(forKey: Self.visionURLKey),
            legacyModel: defaults.string(forKey: Self.visionModelKey)
        )
        loadedEndpoints = vision.endpoints
        loadedVision = vision.visionID
        var seededFromDev = false
        if let dev {
            if let match = loadedEndpoints.first(where: {
                ChatEndpointCatalog.matchesHost($0.completionsURL, dev.completionsURL)
                    && !ChatEndpointCatalog.isOnDevice($0)
            }) {
                if match.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let index = loadedEndpoints.firstIndex(where: { $0.id == match.id })
                {
                    loadedEndpoints[index].model = dev.model
                    seededFromDev = true
                }
            } else {
                let seeded = ChatEndpoint(
                    id: UUID(),
                    name: ChatEndpointCatalog.migratedName,
                    completionsURL: dev.completionsURL,
                    model: dev.model,
                    systemPrompt: ""
                )
                loadedEndpoints.append(seeded)
                seededFromDev = true
            }
        }
        var keys: [UUID: String] = [:]
        for endpoint in loadedEndpoints {
            keys[endpoint.id] = secrets.read(KeychainStore.chatAccount(for: endpoint.id)) ?? ""
        }
        if loadedDefault == nil || !loadedEndpoints.contains(where: { $0.id == loadedDefault }) {
            loadedDefault = ChatEndpointCatalog.resolvedDefault(
                endpoints: loadedEndpoints,
                defaultID: loadedDefault
            )?.id
        }
        var resolvedVisionID = ChatEndpointCatalog.resolvedVision(
            endpoints: loadedEndpoints,
            visionID: loadedVision
        )?.id
        // Old builds kept one shared chat key and one vision key. Copy each only to the provider it
        // belongs to, and delete the shared slot only once a provider holds it: never another host, never lost.
        func takesKey(_ id: UUID?) -> UUID? {
            guard let row = loadedEndpoints.first(where: { $0.id == id }),
                  !ChatEndpointCatalog.isOnDevice(row), !row.usesChatGPTAuth
            else { return nil }
            return row.id
        }
        func migrateLegacy(_ account: String, to target: UUID?) {
            guard let legacy = secrets.read(account), !legacy.isEmpty else { return }
            if let target, (keys[target] ?? "").isEmpty,
               (try? secrets.write(legacy, KeychainStore.chatAccount(for: target))) != nil
            {
                keys[target] = legacy
            }
            if keys.values.contains(legacy) {
                secrets.delete(account)
            }
        }
        let lastChatURL = defaults.string(forKey: ChatSettings.urlKey) ?? ""
        migrateLegacy(KeychainStore.chatAccount, to: takesKey(loadedEndpoints.first {
            !lastChatURL.isEmpty && ChatEndpointCatalog.matchesHost($0.completionsURL, lastChatURL)
        }?.id))
        migrateLegacy(KeychainStore.visionAccount, to: takesKey(resolvedVisionID))
        if let dev {
            if let match = loadedEndpoints.first(where: {
                ChatEndpointCatalog.matchesHost($0.completionsURL, dev.completionsURL)
                    && !ChatEndpointCatalog.isOnDevice($0)
            }), (keys[match.id] ?? "").isEmpty {
                keys[match.id] = dev.apiKey
                try? secrets.write(dev.apiKey, KeychainStore.chatAccount(for: match.id))
            }
        }
        let beforePrune = loadedEndpoints.map(\.id)
        loadedEndpoints = ChatEndpointCatalog.pruningUnusedSeeds(
            loadedEndpoints,
            defaultID: loadedDefault,
            visionID: loadedVision,
            hasSecret: { !(keys[$0] ?? "").isEmpty }
        )
        if beforePrune != loadedEndpoints.map(\.id) {
            seededFromDev = true
        }
        if loadedDefault == nil || !loadedEndpoints.contains(where: { $0.id == loadedDefault }) {
            loadedDefault = ChatEndpointCatalog.resolvedDefault(
                endpoints: loadedEndpoints,
                defaultID: loadedDefault
            )?.id
        }
        resolvedVisionID = ChatEndpointCatalog.resolvedVision(
            endpoints: loadedEndpoints,
            visionID: loadedVision
        )?.id
        var nextVisionURL = defaults.string(forKey: Self.visionURLKey) ?? ""
        if let vision = ChatEndpointCatalog.resolvedVision(endpoints: loadedEndpoints, visionID: resolvedVisionID) {
            nextVisionURL = vision.completionsURL
        }
        var nextChatModel = loaded.chatModelID
        var nextVisionModel = loaded.visionModelID
        if nextChatModel.isEmpty,
           let selected = loadedDefault,
           let row = loadedEndpoints.first(where: { $0.id == selected }),
           !ChatEndpointCatalog.isOnDevice(row)
        {
            nextChatModel = row.model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if nextVisionModel.isEmpty,
           let visionID = resolvedVisionID,
           let row = loadedEndpoints.first(where: { $0.id == visionID }),
           !ChatEndpointCatalog.isOnDevice(row)
        {
            nextVisionModel = row.model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        endpoints = loadedEndpoints
        defaultEndpointID = loadedDefault
        visionEndpointID = resolvedVisionID
        chatModelID = nextChatModel
        apiKeys = keys
        modelListErrors = [:]
        visionModel = nextVisionModel
        visionURL = nextVisionURL
        if defaults.object(forKey: Self.hoverKey) == nil {
            keepHovering = true
        } else {
            keepHovering = defaults.bool(forKey: Self.hoverKey)
        }
        experimentalAgent = ExperimentalAgent.load(from: defaults)
        agentFolderPath = FolderGrant.url(from: defaults).map(FolderGrant.displayPath)
        usesMultilinePrompt = PromptSettings.loadMultiline(from: defaults)
        captureTarget = CaptureTarget(rawValue: defaults.string(forKey: Self.captureKey) ?? "") ?? .screen
        usesMatte = defaults.bool(forKey: Self.matteKey)
        usesNewUI = defaults.bool(forKey: Self.newUIKey) || CommandLine.arguments.contains("--new-ui")
        glassAmount = HUDMaterial.loadAmount(from: defaults)
        defaultSystemPrompt = SystemPrompt.loadGlobal(from: defaults)
        wakeOnAxiom = VoiceSettings.loadWakeOnAxiom(from: defaults)
        pauseToSend = VoiceSettings.loadPauseToSend(from: defaults)
        let historyOn = HistorySettings.loadEnabled(from: defaults)
        savesHistory = historyOn
        savesHistoryScreenshots = historyOn
            ? HistorySettings.loadSaveScreenshots(from: defaults)
            : false
        if !historyOn {
            HistorySettings.saveSaveScreenshots(false, to: defaults)
        }
        debugToolsEnabled = DebugSettings.loadEnabled(from: defaults)
        reasoningEffort = ReasoningEffort.load(from: defaults)
        requestTimeoutSeconds = ChatTimeoutSettings.load(from: defaults)
        historyStore = HistoryStore(root: historyRoot)
        if ChatSettings.loadOnDevice(from: defaults) {
            ChatSettings.saveOnDevice(false, to: defaults)
        }
        if loaded.didMigrate || resolvedVisionID != nil {
            defaults.removeObject(forKey: Self.visionURLKey)
            defaults.removeObject(forKey: Self.visionModelKey)
        }
        if loaded.didMigrate || seededFromDev {
            persistCatalog()
        }
    }

    var allowedCleartextHosts: Set<String> {
        EndpointResolver.cleartextHosts(devHost: devCleartextHost)
    }

    var selectedEndpoint: ChatEndpoint? {
        ChatEndpointCatalog.resolvedDefault(endpoints: endpoints, defaultID: defaultEndpointID)
    }

    var visionEndpoint: ChatEndpoint? {
        ChatEndpointCatalog.resolvedVision(endpoints: endpoints, visionID: visionEndpointID)
    }

    var visionModelID: String {
        get { visionModel }
        set { visionModel = newValue }
    }

    func sendEndpoint(hasImage: Bool) -> ChatEndpoint? {
        sendSelection(hasImage: hasImage).endpoint
    }

    func sendSelection(hasImage: Bool) -> ChatEndpointCatalog.SendSelection {
        ChatEndpointCatalog.resolvedSend(
            endpoints: endpoints,
            chatID: defaultEndpointID,
            chatModelID: chatModelID,
            visionID: visionEndpointID,
            visionModelID: visionModelID,
            hasImage: hasImage
        )
    }

    func visionCredentials() -> ServiceCredentials {
        guard let endpoint = visionEndpoint, !ChatEndpointCatalog.isOnDevice(endpoint) else {
            return ServiceCredentials(url: "", model: "", apiKey: "")
        }
        return ServiceCredentials(
            url: endpoint.completionsURL,
            model: visionModelID,
            apiKey: apiKeys[endpoint.id] ?? "",
            kind: endpoint.kind
        )
    }

    func route(for messages: [OutboundMessage]) -> ChatRoute {
        let hasImage = messages.contains { !$0.imageJPEGs.isEmpty }
        let selection = sendSelection(hasImage: hasImage)
        let vision = visionCredentials()
        return ChatRouting.decide(
            onDevice: selection.usesOnDevice,
            availability: OnDeviceChat.availability,
            cloud: cloudTarget(for: selection, hasImage: hasImage),
            hasImage: hasImage,
            visionConfigured: vision.isComplete,
            supportsOnDeviceImage: OnDeviceChat.supportsImages
        )
    }

    func target(for messages: [OutboundMessage]) -> SendTarget {
        let hasImage = messages.contains { !$0.imageJPEGs.isEmpty }
        return cloudTarget(for: sendSelection(hasImage: hasImage), hasImage: hasImage)
    }

    private func cloudTarget(
        for selection: ChatEndpointCatalog.SendSelection,
        hasImage: Bool
    ) -> SendTarget {
        if selection.usesOnDevice {
            return ChatEndpointCatalog.target(
                endpoint: nil,
                apiKey: "",
                vision: visionCredentials(),
                hasImage: hasImage,
                allowedCleartextHosts: allowedCleartextHosts
            )
        }
        let endpoint = selection.endpoint
        let key = endpoint.flatMap { apiKeys[$0.id] } ?? ""
        return ChatEndpointCatalog.target(
            endpoint: endpoint,
            apiKey: key,
            vision: visionCredentials(),
            hasImage: hasImage,
            allowedCleartextHosts: allowedCleartextHosts,
            modelID: selection.modelID
        )
    }

    var blockingMessage: String? {
        switch route(for: []) {
        case .blocked(let message):
            return message
        case .onDevice:
            return nil
        case .cloud(let target):
            if case .blocked(let message) = target {
                return message
            }
            return nil
        }
    }

    func save() {
        persistCatalog()
        saveVision()
    }

    func setAgentMode(id: UUID, on: Bool) {
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        var endpoint = endpoints[index]
        endpoint.prefersAgent = on
        endpoint.enablesTools = on
        endpoints[index] = endpoint
        persistCatalog()
    }

    func setDefault(_ id: UUID) {
        guard let endpoint = endpoints.first(where: { $0.id == id }) else { return }
        defaultEndpointID = id
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            chatModelID = ""
        } else {
            chatModelID = ModelList.selectModel(saved: chatModelID, models: endpoint.availableModels)
        }
        persistCatalog()
    }

    func selectChat(providerID: UUID, modelID: String) {
        guard endpoints.contains(where: { $0.id == providerID }) else { return }
        let next = HUDModelMenu.selecting(
            providerID: providerID,
            modelID: modelID,
            in: ChatModelSelection(
                chatID: defaultEndpointID,
                chatModelID: chatModelID,
                visionID: visionEndpointID,
                visionModelID: visionModelID
            )
        )
        defaultEndpointID = next.chatID
        chatModelID = next.chatModelID
        persistCatalog()
    }

    func setVision(_ id: UUID) {
        guard endpoints.contains(where: { $0.id == id }) else { return }
        visionEndpointID = id
        let endpoint = endpoints.first(where: { $0.id == id })
        if endpoint.map(ChatEndpointCatalog.isOnDevice) == true {
            visionModel = ""
            visionURL = ""
        } else if let endpoint {
            visionURL = endpoint.completionsURL
            visionModel = ModelList.selectModel(saved: visionModel, models: endpoint.availableModels)
        }
        persistCatalog()
        saveVision()
    }

    func clearVisionSelection() {
        visionEndpointID = nil
        visionModel = ""
        visionURL = ""
        persistCatalog()
        saveVision()
    }

    func draftEndpoint(for choice: EndpointAddChoice = .custom) -> ChatEndpoint {
        EndpointAddPolicy.draft(for: choice)
    }

    @discardableResult
    func saveEndpoint(_ endpoint: ChatEndpoint, apiKey: String) -> String? {
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            return nil
        }
        let isNew = !endpoints.contains(where: { $0.id == endpoint.id })
        var updated = endpoint
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.completionsURL = updated.completionsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.model = updated.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let rejection = EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: updated.kind,
                name: updated.name,
                completionsURL: updated.completionsURL,
                model: updated.model,
                isNew: isNew,
                hasChatGPTToken: ChatGPTAuth.parse(apiKey) != nil || ChatGPTAuth.parse(apiKeys[updated.id] ?? "") != nil
            )
        )
        if let rejection {
            return rejection
        }
        if let index = endpoints.firstIndex(where: { $0.id == updated.id }) {
            if updated.availableModels.isEmpty {
                updated.availableModels = endpoints[index].availableModels
            }
            endpoints[index] = updated
        } else {
            endpoints.append(updated)
        }
        var keyError: String?
        // Clearing a key that loaded removes it. An empty field for a key that never loaded leaves the
        // Keychain alone, and ChatGPT keeps its sign-in unless a new one arrives.
        let clearsLoadedKey = apiKey.isEmpty && !(apiKeys[updated.id] ?? "").isEmpty
        if updated.kind == .chatgptSubscription {
            if ChatGPTAuth.parse(apiKey) != nil {
                keyError = writeChatKey(apiKey, id: updated.id)
            }
        } else if !apiKey.isEmpty || clearsLoadedKey {
            keyError = writeChatKey(apiKey, id: updated.id)
        }
        persistCatalog()
        return keyError
    }

    func replaceChatSecret(_ value: String, id: UUID) {
        guard !value.isEmpty else { return }
        _ = writeChatKey(value, id: id)
    }

    func clearChatSecret(id: UUID) {
        apiKeys[id] = ""
        secrets.delete(KeychainStore.chatAccount(for: id))
    }

    func applyListedModels(
        _ models: [String],
        to id: UUID,
        triedPath: String? = nil,
        configuredURL: String? = nil
    ) {
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        if ModelList.isFailed(models: models) {
            let url = configuredURL ?? endpoints[index].completionsURL
            let guidance = EndpointURLWarning.message(for: url)
            modelListErrors[id] = ModelList.failureMessage(triedPath: triedPath, guidance: guidance)
            return
        }
        modelListErrors[id] = nil
        endpoints[index] = ModelList.apply(models: models, to: endpoints[index])
        if defaultEndpointID == id {
            chatModelID = ModelList.selectModel(saved: chatModelID, models: models)
        }
        if visionEndpointID == id {
            visionModel = ModelList.selectModel(saved: visionModel, models: models)
        }
        persistCatalog()
    }

    func refreshModels(for id: UUID) async {
        guard let endpoint = endpoints.first(where: { $0.id == id }) else { return }
        var secret = apiKeys[id] ?? ""
        // An expired ChatGPT sign-in would list nothing until the next send refreshed it.
        if endpoint.usesChatGPTAuth, let fresh = try? await ChatGPTAuth.freshCredential(secret) {
            // Still fresh: nothing to store, and no Keychain write.
            if ChatGPTAuth.parse(secret)?.access != fresh.access {
                secret = ChatGPTAuth.serialize(fresh)
                replaceChatSecret(secret, id: id)
            }
        }
        let client = ModelListClient()
        let result = await client.list(
            endpoint: endpoint,
            secret: secret,
            allowedCleartextHosts: allowedCleartextHosts
        )
        client.session.finishTasksAndInvalidate()
        applyListedModels(
            result.models,
            to: id,
            triedPath: result.triedPath,
            configuredURL: endpoint.completionsURL
        )
    }

    func deleteEndpoint(_ id: UUID) {
        guard id != ChatEndpointCatalog.onDeviceID else { return }
        endpoints = ChatEndpointCatalog.removing(id, from: endpoints)
        apiKeys[id] = nil
        modelListErrors[id] = nil
        secrets.delete(KeychainStore.chatAccount(for: id))
        if defaultEndpointID == id {
            defaultEndpointID = ChatEndpointCatalog.resolvedDefault(
                endpoints: endpoints,
                defaultID: nil
            )?.id
            if let next = endpoints.first(where: { $0.id == defaultEndpointID }) {
                chatModelID = ChatEndpointCatalog.isOnDevice(next)
                    ? ""
                    : ModelList.selectModel(saved: "", models: next.availableModels)
            } else {
                chatModelID = ""
            }
        }
        if visionEndpointID == id {
            visionEndpointID = nil
            visionURL = ""
            visionModel = ""
            saveVision()
        }
        persistCatalog()
    }

    /// Whether the card shows Ask and Agent. One rule for the toolbar, the pills, and the shortcut.
    var showsPresetControl: Bool {
        AgentModePolicy.showsPresetControl(experimental: experimentalAgent, prefersAgent: prefersAgent)
    }

    var startingPreset: Preset {
        AgentModePolicy.preset(experimental: experimentalAgent, prefersAgent: prefersAgent)
    }

    private var prefersAgent: Bool {
        sendEndpoint(hasImage: false)?.prefersAgent == true
    }

    func apiKey(for id: UUID) -> String {
        apiKeys[id] ?? ""
    }

    private func persistCatalog() {
        ChatEndpointCatalog.save(
            endpoints: endpoints,
            defaultID: defaultEndpointID,
            visionID: visionEndpointID,
            chatModelID: chatModelID,
            visionModelID: visionModel,
            to: defaults
        )
        if let selected = selectedEndpoint, !ChatEndpointCatalog.isOnDevice(selected) {
            defaults.set(chatModelID, forKey: ChatSettings.modelKey)
            defaults.set(selected.completionsURL, forKey: ChatSettings.urlKey)
        }
    }

    /// Returns an error to show when the Keychain refuses the key. It still works until Axiom quits.
    private func writeChatKey(_ value: String, id: UUID) -> String? {
        apiKeys[id] = value
        let account = KeychainStore.chatAccount(for: id)
        if value.isEmpty {
            secrets.delete(account)
            return nil
        }
        do {
            try secrets.write(value, account)
            return nil
        } catch {
            return String(localized: "The key works until Axiom quits, but the Keychain did not save it.")
        }
    }

    private func saveVision() {
        visionModel = visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        visionURL = visionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(visionModel, forKey: Self.visionModelKey)
        defaults.set(visionURL, forKey: Self.visionURLKey)
    }
}

enum SendTarget: Equatable {
    case ready(url: URL, model: String, apiKey: String, kind: CloudSendKind)
    case blocked(String)
}
