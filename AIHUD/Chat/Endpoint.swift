import Foundation

enum EndpointError: Equatable, Error {
    case empty
    case unsupportedScheme
    case fileURL
    case insecureHost
}

enum EndpointKind: String, Codable, Equatable, Hashable, Sendable {
    case onDevice
    case openaiCompatible
    case anthropic
    case chatgptSubscription
}

enum CloudSendKind: String, Equatable, Sendable {
    case openaiCompletions
    case anthropicMessages
    case chatgptResponses
}

enum EndpointURLWarning {
    static let message =
        "This looks like a chat URL. Use the API base https://host/v1."
    static let openaiHint =
        "Base URL only, for example https://host/v1."
    static let anthropicHint =
        "Base URL only, for example https://host/v1."
    static let customHint =
        "Base URL only, for example https://host/v1. OpenAI chat is /v1/chat/completions; Anthropic messages are /v1/messages."

    static func message(for configured: String) -> String? {
        looksLikeChatEndpointURL(configured) ? message : nil
    }

    static func hint(for kind: EndpointKind, presetID: String?) -> String? {
        switch kind {
        case .onDevice, .chatgptSubscription:
            return nil
        case .anthropic:
            return anthropicHint
        case .openaiCompatible:
            return presetID == nil ? customHint : openaiHint
        }
    }

    /// True when the field looks like a chat/messages endpoint instead of an API base.
    static func looksLikeChatEndpointURL(_ configured: String) -> Bool {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var beforeQuery = trimmed
        if let hash = beforeQuery.firstIndex(of: "#") {
            beforeQuery = String(beforeQuery[..<hash])
        }
        if let query = beforeQuery.firstIndex(of: "?") {
            beforeQuery = String(beforeQuery[..<query])
        }
        while beforeQuery.count > 1 && beforeQuery.hasSuffix("/") {
            beforeQuery.removeLast()
        }

        if beforeQuery.range(of: #"(?i)/models$"#, options: .regularExpression) != nil {
            return false
        }
        if beforeQuery.range(of: #"(?i)/chat/completions"#, options: .regularExpression) != nil {
            return true
        }
        if beforeQuery.range(of: #"(?i)/completions$"#, options: .regularExpression) != nil {
            return true
        }
        if beforeQuery.range(of: #"(?i)/messages$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}

enum EndpointResolver {
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// `configured` is either a base URL or a full chat completions URL.
    /// Cleartext is allowed for loopback and for `allowedCleartextHosts`.
    static func completionsURL(
        configured: String,
        allowedCleartextHosts: Set<String> = []
    ) -> Result<URL, EndpointError> {
        join(
            configured: configured,
            suffix: ["chat", "completions"],
            allowedCleartextHosts: allowedCleartextHosts
        )
    }

    /// Models list URL. Strips a trailing chat/messages path so a pasted
    /// `/v1/chat/completions` or `/v1/messages` still lists `/v1/models`.
    /// Does not rewrite the stored Settings string.
    static func modelsURL(
        configured: String,
        allowedCleartextHosts: Set<String> = []
    ) -> Result<URL, EndpointError> {
        join(
            configured: apiBaseForModels(configured),
            suffix: ["models"],
            allowedCleartextHosts: allowedCleartextHosts
        )
    }

    static func messagesURL(
        configured: String,
        allowedCleartextHosts: Set<String> = []
    ) -> Result<URL, EndpointError> {
        join(configured: configured, suffix: ["messages"], allowedCleartextHosts: allowedCleartextHosts)
    }

    static func responsesURL(
        configured: String,
        allowedCleartextHosts: Set<String> = []
    ) -> Result<URL, EndpointError> {
        join(configured: configured, suffix: ["responses"], allowedCleartextHosts: allowedCleartextHosts)
    }

    /// Drop a trailing chat or messages path before joining `/models`.
    static func apiBaseForModels(_ configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard var components = URLComponents(string: trimmed) else { return trimmed }

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.range(of: #"(?i)/models$"#, options: .regularExpression) != nil {
            return trimmed
        }
        if let range = path.range(of: #"(?i)/chat/completions$"#, options: .regularExpression) {
            path = String(path[..<range.lowerBound])
        } else if let range = path.range(of: #"(?i)/completions$"#, options: .regularExpression) {
            path = String(path[..<range.lowerBound])
        } else if let range = path.range(of: #"(?i)/messages$"#, options: .regularExpression) {
            path = String(path[..<range.lowerBound])
        }
        if path.isEmpty {
            path = "/"
        }
        components.path = path
        return components.string ?? trimmed
    }

    static func join(
        configured: String,
        suffix: [String],
        allowedCleartextHosts: Set<String> = []
    ) -> Result<URL, EndpointError> {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased()
        else {
            return .failure(.unsupportedScheme)
        }
        if scheme == "file" { return .failure(.fileURL) }
        guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme) }
        guard let rawHost = components.host?.lowercased(), !rawHost.isEmpty else {
            return .failure(.unsupportedScheme)
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if scheme == "http" {
            let allowed = loopbackHosts.union(allowedCleartextHosts.map { $0.lowercased() })
            if !allowed.contains(host) {
                return .failure(.insecureHost)
            }
        }

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        let parts = path.split(separator: "/").map(String.init)
        if parts.suffix(suffix.count) == suffix[...] {
            components.path = path
            guard let url = components.url else { return .failure(.unsupportedScheme) }
            return .success(url)
        }

        components.path = path
        guard let base = components.url else { return .failure(.unsupportedScheme) }
        let joined = suffix.reduce(base) { $0.appendingPathComponent($1) }
        return .success(joined)
    }
}

struct EndpointPreset: Equatable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var kind: EndpointKind
    var requiresAPIKey: Bool
}

struct ChatEndpoint: Equatable, Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var completionsURL: String
    var model: String
    var systemPrompt: String
    var kind: EndpointKind
    var presetID: String?
    var availableModels: [String]

    init(
        id: UUID,
        name: String,
        completionsURL: String,
        model: String,
        systemPrompt: String,
        kind: EndpointKind = .openaiCompatible,
        presetID: String? = nil,
        availableModels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.completionsURL = completionsURL
        self.model = model
        self.systemPrompt = systemPrompt
        self.kind = kind
        self.presetID = presetID
        self.availableModels = availableModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        completionsURL = try container.decode(String.self, forKey: .completionsURL)
        model = try container.decode(String.self, forKey: .model)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
        availableModels = try container.decodeIfPresent([String].self, forKey: .availableModels) ?? []
        if let kind = try container.decodeIfPresent(EndpointKind.self, forKey: .kind) {
            self.kind = kind
        } else if id == ChatEndpointCatalog.onDeviceID {
            kind = .onDevice
        } else {
            kind = .openaiCompatible
        }
    }

    var hostLabel: String {
        if kind == .onDevice || ChatEndpointCatalog.isOnDevice(self) {
            return "On this Mac"
        }
        return URL(string: completionsURL)?.host ?? ""
    }

    var modelLabel: String {
        if kind == .onDevice || ChatEndpointCatalog.isOnDevice(self) {
            return "Apple Intelligence"
        }
        return model
    }

    var urlIsFixed: Bool {
        kind == .onDevice || kind == .chatgptSubscription
    }

    var usesChatGPTAuth: Bool {
        kind == .chatgptSubscription
    }
}

struct EndpointDraft: Equatable, Sendable {
    var kind: EndpointKind
    var name: String
    var completionsURL: String
    var model: String
    var isNew: Bool
    var hasChatGPTToken: Bool
}

enum EndpointSavePolicy {
    static func rejection(_ draft: EndpointDraft) -> String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = draft.completionsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.kind {
        case .onDevice:
            return nil
        case .chatgptSubscription:
            if draft.isNew && !draft.hasChatGPTToken {
                return "Sign in to ChatGPT."
            }
            if name.isEmpty {
                return "Add a name."
            }
            return nil
        case .openaiCompatible, .anthropic:
            if name.isEmpty { return "Add a name." }
            if url.isEmpty { return "Add a base URL." }
            return nil
        }
    }
}

enum EndpointTableAction: Equatable, Sendable {
    case highlight(UUID)
    case edit(UUID)
    case makeDefault(UUID)
    case setVision(UUID)
}

enum EndpointTablePolicy {
    struct Result: Equatable, Sendable {
        var defaultID: UUID?
        var visionID: UUID?
        var opensEditor: UUID?
    }

    static func apply(
        _ action: EndpointTableAction,
        defaultID: UUID?,
        visionID: UUID?
    ) -> Result {
        switch action {
        case .highlight:
            return Result(defaultID: defaultID, visionID: visionID, opensEditor: nil)
        case .edit(let id):
            return Result(
                defaultID: defaultID,
                visionID: visionID,
                opensEditor: allowsEdit(id) ? id : nil
            )
        case .makeDefault(let id):
            return Result(defaultID: id, visionID: visionID, opensEditor: nil)
        case .setVision(let id):
            return Result(defaultID: defaultID, visionID: id, opensEditor: nil)
        }
    }

    static func allowsEdit(_ id: UUID) -> Bool {
        id != ChatEndpointCatalog.onDeviceID
    }
}

enum EndpointAddChoice: Equatable, Sendable {
    case custom
    case preset(String)
}

enum EndpointAddPolicy {
    static func draft(for choice: EndpointAddChoice) -> ChatEndpoint {
        switch choice {
        case .custom:
            return ChatEndpoint(
                id: UUID(),
                name: "",
                completionsURL: "",
                model: "",
                systemPrompt: "",
                kind: .openaiCompatible
            )
        case .preset(let id):
            guard let preset = ChatEndpointCatalog.cloudPresets.first(where: { $0.id == id }) else {
                return draft(for: .custom)
            }
            return ChatEndpoint(
                id: UUID(),
                name: preset.name,
                completionsURL: preset.baseURL,
                model: "",
                systemPrompt: "",
                kind: preset.kind,
                presetID: preset.id
            )
        }
    }
}

struct ChatEndpointCatalog: Equatable, Sendable {
    static let endpointsKey = "chat.endpoints"
    static let defaultIDKey = "chat.defaultEndpointID"
    static let visionIDKey = "chat.visionEndpointID"
    static let chatModelIDKey = "chat.chatModelID"
    static let visionModelIDKey = "chat.visionModelID"
    static let migratedName = "Default"
    static let missingEndpointMessage = "Choose a chat model in Settings"
    static let onDeviceID = UUID(uuidString: "00000000-0000-4000-A1D0-000000000001")!
    static let onDeviceName = "On-device"

    static let cloudPresets: [EndpointPreset] = [
        EndpointPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com/v1", kind: .anthropic, requiresAPIKey: true),
        EndpointPreset(id: "chatgpt", name: "ChatGPT", baseURL: "https://chatgpt.com/backend-api/codex", kind: .chatgptSubscription, requiresAPIKey: false),
        EndpointPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "venice", name: "Venice", baseURL: "https://api.venice.ai/api/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "moonshot", name: "Moonshot AI", baseURL: "https://api.moonshot.ai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "zai", name: "Z.AI", baseURL: "https://api.z.ai/api/paas/v4", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "alibaba_cloud", name: "Alibaba Cloud Model Studio", baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "siliconflow", name: "SiliconFlow", baseURL: "https://api.siliconflow.com/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "cohere", name: "Cohere", baseURL: "https://api.cohere.ai/compatibility/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "xai", name: "xAI", baseURL: "https://api.x.ai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "together", name: "Together AI", baseURL: "https://api.together.xyz/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "fireworks", name: "Fireworks AI", baseURL: "https://api.fireworks.ai/inference/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "cerebras", name: "Cerebras", baseURL: "https://api.cerebras.ai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "meta", name: "Meta Muse", baseURL: "https://api.meta.ai/v1", kind: .openaiCompatible, requiresAPIKey: true),
        EndpointPreset(id: "lmstudio", name: "LM Studio", baseURL: "http://127.0.0.1:1234/v1", kind: .openaiCompatible, requiresAPIKey: false),
        EndpointPreset(id: "ollama", name: "Ollama", baseURL: "http://127.0.0.1:11434/v1", kind: .openaiCompatible, requiresAPIKey: false),
        EndpointPreset(id: "unsloth", name: "Unsloth", baseURL: "http://127.0.0.1:8888/v1", kind: .openaiCompatible, requiresAPIKey: true)
    ]

    static var onDeviceEndpoint: ChatEndpoint {
        ChatEndpoint(
            id: onDeviceID,
            name: onDeviceName,
            completionsURL: "",
            model: "",
            systemPrompt: "",
            kind: .onDevice,
            presetID: "apple_foundation"
        )
    }

    var endpoints: [ChatEndpoint]
    var defaultID: UUID?
    var visionID: UUID?
    var chatModelID: String = ""
    var visionModelID: String = ""
    var didMigrate: Bool

    static func isOnDevice(_ endpoint: ChatEndpoint) -> Bool {
        endpoint.id == onDeviceID || endpoint.kind == .onDevice
    }

    static func ensuringOnDevice(_ endpoints: [ChatEndpoint]) -> [ChatEndpoint] {
        let others = endpoints.filter { $0.id != onDeviceID && $0.kind != .onDevice }
        return [onDeviceEndpoint] + others
    }

    static func ensuringCatalog(_ endpoints: [ChatEndpoint]) -> [ChatEndpoint] {
        ensuringOnDevice(endpoints).map(inferPreset)
    }

    static func applyingSaved(_ endpoint: ChatEndpoint, to endpoints: [ChatEndpoint]) -> [ChatEndpoint] {
        var rows = ensuringOnDevice(endpoints)
        if let index = rows.firstIndex(where: { $0.id == endpoint.id }) {
            rows[index] = endpoint
        } else {
            rows.append(endpoint)
        }
        return ensuringOnDevice(rows)
    }

    static func pruningUnusedSeeds(
        _ endpoints: [ChatEndpoint],
        defaultID: UUID? = nil,
        visionID: UUID? = nil,
        hasSecret: (UUID) -> Bool = { _ in false }
    ) -> [ChatEndpoint] {
        ensuringOnDevice(endpoints).filter { endpoint in
            if isOnDevice(endpoint) { return true }
            return !isUnusedSeed(
                endpoint,
                defaultID: defaultID,
                visionID: visionID,
                hasSecret: hasSecret(endpoint.id)
            )
        }
    }

    static func isUnusedSeed(
        _ endpoint: ChatEndpoint,
        defaultID: UUID? = nil,
        visionID: UUID? = nil,
        hasSecret: Bool = false
    ) -> Bool {
        if isOnDevice(endpoint) { return false }
        if hasSecret { return false }
        if defaultID == endpoint.id { return false }
        if visionID == endpoint.id { return false }
        if !endpoint.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if !endpoint.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if !endpoint.availableModels.isEmpty { return false }
        guard let presetID = endpoint.presetID,
              let preset = cloudPresets.first(where: { $0.id == presetID })
        else {
            return false
        }
        let stockName = endpoint.name == preset.name
        let stockURL = matchesHost(endpoint.completionsURL, preset.baseURL)
        let seederID = endpoint.id == presetUUID(preset.id)
        return seederID && stockName && stockURL
    }

    static func seededEndpoint(_ preset: EndpointPreset) -> ChatEndpoint {
        ChatEndpoint(
            id: presetUUID(preset.id),
            name: preset.name,
            completionsURL: preset.baseURL,
            model: "",
            systemPrompt: "",
            kind: preset.kind,
            presetID: preset.id
        )
    }

    static func removing(_ id: UUID, from endpoints: [ChatEndpoint]) -> [ChatEndpoint] {
        ensuringOnDevice(endpoints.filter { $0.id != id })
    }

    static func usesOnDevice(endpoints: [ChatEndpoint], defaultID: UUID?) -> Bool {
        resolvedDefault(endpoints: endpoints, defaultID: defaultID)?.id == onDeviceID
    }

    static func resolvedDefault(endpoints: [ChatEndpoint], defaultID: UUID?) -> ChatEndpoint? {
        if let defaultID, let match = endpoints.first(where: { $0.id == defaultID }) {
            return match
        }
        return endpoints.first(where: { $0.id != onDeviceID }) ?? endpoints.first
    }

    static func resolvedVision(endpoints: [ChatEndpoint], visionID: UUID?) -> ChatEndpoint? {
        guard let visionID else { return nil }
        return endpoints.first(where: { $0.id == visionID })
    }

    struct SendSelection: Equatable, Sendable {
        var endpoint: ChatEndpoint?
        var modelID: String

        var usesOnDevice: Bool {
            endpoint.map(isOnDevice) ?? false
        }
    }

    static func resolvedSend(
        endpoints: [ChatEndpoint],
        chatID: UUID?,
        chatModelID: String,
        visionID: UUID?,
        visionModelID: String,
        hasImage: Bool
    ) -> SendSelection {
        let chat = resolvedDefault(endpoints: endpoints, defaultID: chatID)
        let chatModel = chat.map(isOnDevice) == true
            ? ""
            : chatModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasImage, let vision = resolvedVision(endpoints: endpoints, visionID: visionID) {
            if isOnDevice(vision) {
                return SendSelection(endpoint: vision, modelID: "")
            }
            let visionModel = visionModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !visionModel.isEmpty {
                return SendSelection(endpoint: vision, modelID: visionModel)
            }
        }
        return SendSelection(endpoint: chat, modelID: chatModel)
    }

    static func requiresAPIKey(_ endpoint: ChatEndpoint) -> Bool {
        if isOnDevice(endpoint) || endpoint.kind == .chatgptSubscription {
            return false
        }
        if let preset = cloudPresets.first(where: { $0.id == endpoint.presetID }) {
            return preset.requiresAPIKey
        }
        return true
    }

    static func decodedEndpoints(from defaults: UserDefaults) -> [ChatEndpoint]? {
        guard let data = defaults.data(forKey: endpointsKey) else { return nil }
        return try? JSONDecoder().decode([ChatEndpoint].self, from: data)
    }

    static func load(from defaults: UserDefaults) -> ChatEndpointCatalog {
        migrate(
            stored: defaults.data(forKey: endpointsKey),
            defaultID: defaults.string(forKey: defaultIDKey),
            legacyURL: defaults.string(forKey: ChatSettings.urlKey),
            legacyModel: defaults.string(forKey: ChatSettings.modelKey),
            onDeviceWasEnabled: ChatSettings.loadOnDevice(from: defaults),
            visionID: defaults.string(forKey: visionIDKey),
            legacyVisionURL: defaults.string(forKey: "endpoint.visionURL"),
            legacyVisionModel: defaults.string(forKey: "endpoint.visionModel"),
            chatModelID: defaults.string(forKey: chatModelIDKey),
            visionModelID: defaults.string(forKey: visionModelIDKey)
        )
    }

    static func save(
        endpoints: [ChatEndpoint],
        defaultID: UUID?,
        visionID: UUID? = nil,
        chatModelID: String = "",
        visionModelID: String = "",
        to defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(endpoints) {
            defaults.set(data, forKey: endpointsKey)
        }
        if let defaultID {
            defaults.set(defaultID.uuidString, forKey: defaultIDKey)
        } else {
            defaults.removeObject(forKey: defaultIDKey)
        }
        if let visionID {
            defaults.set(visionID.uuidString, forKey: visionIDKey)
        } else {
            defaults.removeObject(forKey: visionIDKey)
        }
        defaults.set(chatModelID, forKey: chatModelIDKey)
        defaults.set(visionModelID, forKey: visionModelIDKey)
    }

    static func migrate(
        stored: Data?,
        defaultID: String?,
        legacyURL: String?,
        legacyModel: String?,
        onDeviceWasEnabled: Bool = false,
        visionID: String? = nil,
        legacyVisionURL: String? = nil,
        legacyVisionModel: String? = nil,
        chatModelID: String? = nil,
        visionModelID: String? = nil
    ) -> ChatEndpointCatalog {
        let parsedDefault = defaultID.flatMap(UUID.init(uuidString:))
        let parsedVision = visionID.flatMap(UUID.init(uuidString:))
        let base: [ChatEndpoint]
        var didMigrate = false
        if let stored, let endpoints = try? JSONDecoder().decode([ChatEndpoint].self, from: stored) {
            base = endpoints
            let insertedOnDevice = !endpoints.contains(where: { $0.id == onDeviceID })
            didMigrate = insertedOnDevice || onDeviceWasEnabled
        } else {
            let url = legacyURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = legacyModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty && model.isEmpty {
                base = []
            } else {
                base = [
                    ChatEndpoint(
                        id: UUID(),
                        name: migratedName,
                        completionsURL: url,
                        model: model,
                        systemPrompt: ""
                    )
                ]
                didMigrate = true
            }
        }
        let before = base
        let inferred = ensuringCatalog(base)
        let seeded = pruningUnusedSeeds(
            inferred,
            defaultID: parsedDefault,
            visionID: parsedVision
        )
        if seeded.map(\.id) != ensuringOnDevice(before).map(\.id)
            || seeded.map(\.presetID) != ensuringOnDevice(before).map(\.presetID)
        {
            didMigrate = true
        }
        let vision = migrateVision(
            endpoints: seeded,
            visionID: parsedVision,
            legacyURL: legacyVisionURL,
            legacyModel: legacyVisionModel
        )
        didMigrate = didMigrate || vision.didMigrate
        let selected = onDeviceWasEnabled ? onDeviceID : resolvedDefault(
            endpoints: vision.endpoints,
            defaultID: parsedDefault
        )?.id
        let chatRow = vision.endpoints.first(where: { $0.id == selected })
        let visionRow = vision.endpoints.first(where: { $0.id == vision.visionID })
        let chatMigrated = migratedModelID(stored: chatModelID, endpoint: chatRow)
        let visionMigrated = migratedModelID(stored: visionModelID, endpoint: visionRow)
        didMigrate = didMigrate || chatMigrated.didMigrate || visionMigrated.didMigrate
        return ChatEndpointCatalog(
            endpoints: vision.endpoints,
            defaultID: selected,
            visionID: vision.visionID,
            chatModelID: chatMigrated.value,
            visionModelID: visionMigrated.value,
            didMigrate: didMigrate
        )
    }

    private static func migratedModelID(
        stored: String?,
        endpoint: ChatEndpoint?
    ) -> (value: String, didMigrate: Bool) {
        if let stored {
            return (stored.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        guard let endpoint, !isOnDevice(endpoint) else {
            return ("", false)
        }
        let fromRow = endpoint.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return (fromRow, !fromRow.isEmpty)
    }

    static func migrateVision(
        endpoints: [ChatEndpoint],
        visionID: UUID?,
        legacyURL: String?,
        legacyModel: String?
    ) -> (endpoints: [ChatEndpoint], visionID: UUID?, didMigrate: Bool) {
        if let visionID, let match = resolvedVision(endpoints: endpoints, visionID: visionID) {
            return (endpoints, match.id, false)
        }
        let url = legacyURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = legacyModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty || !model.isEmpty else {
            return (endpoints, nil, false)
        }
        if let existing = endpoints.first(where: { matchesHost($0.completionsURL, url) && !isOnDevice($0) }) {
            return (endpoints, existing.id, true)
        }
        let row = ChatEndpoint(
            id: UUID(),
            name: "Vision",
            completionsURL: url,
            model: model,
            systemPrompt: ""
        )
        return (endpoints + [row], row.id, true)
    }

    static func target(
        endpoint: ChatEndpoint?,
        apiKey: String,
        vision: ServiceCredentials,
        hasImage: Bool,
        allowedCleartextHosts: Set<String>,
        modelID: String? = nil
    ) -> SendTarget {
        if hasImage, ModelChoice.visionIsIncomplete(vision) {
            return .blocked("Finish the vision model in Settings")
        }
        guard let endpoint, !isOnDevice(endpoint) else {
            if hasImage, vision.isComplete {
                return resolve(credentials: vision, usingVision: true, allowedCleartextHosts: allowedCleartextHosts)
            }
            return .blocked(missingEndpointMessage)
        }
        let chat = ServiceCredentials(
            url: endpoint.completionsURL,
            model: modelID ?? endpoint.model,
            apiKey: apiKey,
            kind: endpoint.kind
        )
        let chosen = ModelChoice.pick(chat: chat, vision: vision, hasImage: hasImage)
        let usingVision = hasImage && vision.isComplete
        return resolve(credentials: chosen, usingVision: usingVision, allowedCleartextHosts: allowedCleartextHosts)
    }

    private static func resolve(
        credentials: ServiceCredentials,
        usingVision: Bool,
        allowedCleartextHosts: Set<String>
    ) -> SendTarget {
        let urlResult: Result<URL, EndpointError>
        let kind: CloudSendKind
        switch credentials.kind {
        case .anthropic:
            urlResult = EndpointResolver.messagesURL(
                configured: credentials.url,
                allowedCleartextHosts: allowedCleartextHosts
            )
            kind = .anthropicMessages
        case .chatgptSubscription:
            urlResult = EndpointResolver.responsesURL(
                configured: credentials.url,
                allowedCleartextHosts: allowedCleartextHosts
            )
            kind = .chatgptResponses
        case .openaiCompatible, .onDevice:
            urlResult = EndpointResolver.completionsURL(
                configured: credentials.url,
                allowedCleartextHosts: allowedCleartextHosts
            )
            kind = .openaiCompletions
        }
        switch urlResult {
        case .success(let url):
            let modelID = credentials.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if modelID.isEmpty {
                return .blocked(usingVision ? "Finish the vision model in Settings" : "Add a model id in Settings")
            }
            if credentials.kind == .chatgptSubscription {
                guard ChatGPTAuth.parse(credentials.apiKey) != nil else {
                    return .blocked("Sign in to ChatGPT in Settings")
                }
            } else if requiresSecret(credentials), credentials.apiKey.isEmpty {
                return .blocked(usingVision ? "Finish the vision model in Settings" : "Add an API key in Settings")
            }
            return .ready(url: url, model: modelID, apiKey: credentials.apiKey, kind: kind)
        case .failure:
            return .blocked(usingVision ? "Check the vision URL in Settings" : "Check the base URL in Settings")
        }
    }

    private static func requiresSecret(_ credentials: ServiceCredentials) -> Bool {
        if credentials.kind == .chatgptSubscription || credentials.kind == .onDevice {
            return false
        }
        if let host = URL(string: credentials.url)?.host?.lowercased(),
           EndpointResolver.loopbackHosts.contains(host)
        {
            return cloudPresets.first(where: { matchesHost(credentials.url, $0.baseURL) })?.requiresAPIKey ?? false
        }
        return true
    }

    private static func inferPreset(_ endpoint: ChatEndpoint) -> ChatEndpoint {
        var next = endpoint
        if next.id == onDeviceID {
            next.kind = .onDevice
            next.presetID = next.presetID ?? "apple_foundation"
            return next
        }
        if next.presetID != nil { return next }
        if let preset = cloudPresets.first(where: { matchesHost(next.completionsURL, $0.baseURL) }) {
            next.presetID = preset.id
            next.kind = preset.kind
        }
        return next
    }

    static func matchesHost(_ lhs: String, _ rhs: String) -> Bool {
        normalizedHostPath(lhs) != nil && normalizedHostPath(lhs) == normalizedHostPath(rhs)
    }

    private static func normalizedHostPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return host + port + path.lowercased()
    }

    private static func presetUUID(_ presetID: String) -> UUID {
        let map: [String: String] = [
            "openai": "00000000-0000-4000-A1D0-000000000010",
            "anthropic": "00000000-0000-4000-A1D0-000000000011",
            "chatgpt": "00000000-0000-4000-A1D0-000000000012",
            "openrouter": "00000000-0000-4000-A1D0-000000000013",
            "venice": "00000000-0000-4000-A1D0-000000000014",
            "moonshot": "00000000-0000-4000-A1D0-000000000015",
            "zai": "00000000-0000-4000-A1D0-000000000016",
            "deepseek": "00000000-0000-4000-A1D0-000000000017",
            "alibaba_cloud": "00000000-0000-4000-A1D0-000000000018",
            "siliconflow": "00000000-0000-4000-A1D0-000000000019",
            "cohere": "00000000-0000-4000-A1D0-00000000001A",
            "groq": "00000000-0000-4000-A1D0-00000000001B",
            "xai": "00000000-0000-4000-A1D0-00000000001C",
            "together": "00000000-0000-4000-A1D0-00000000001D",
            "fireworks": "00000000-0000-4000-A1D0-00000000001E",
            "cerebras": "00000000-0000-4000-A1D0-00000000001F",
            "mistral": "00000000-0000-4000-A1D0-000000000020",
            "meta": "00000000-0000-4000-A1D0-000000000021",
            "lmstudio": "00000000-0000-4000-A1D0-000000000022",
            "ollama": "00000000-0000-4000-A1D0-000000000023",
            "unsloth": "00000000-0000-4000-A1D0-000000000024"
        ]
        return UUID(uuidString: map[presetID] ?? "00000000-0000-4000-A1D0-0000000000FF")!
    }
}

enum RedirectPolicy {
    /// Same host only. An https request may not follow an http redirect.
    static func allows(originalHost: String, originalScheme: String? = nil, next: URL) -> Bool {
        guard let host = next.host, !host.isEmpty else { return false }
        guard host.compare(originalHost, options: .caseInsensitive) == .orderedSame else { return false }
        switch next.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return originalScheme?.lowercased() == "http"
        default:
            return false
        }
    }
}
