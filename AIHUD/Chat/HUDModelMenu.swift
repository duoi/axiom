import Foundation

struct ChatModelSelection: Equatable, Sendable {
    var chatID: UUID?
    var chatModelID: String
    var visionID: UUID?
    var visionModelID: String
}

enum ProviderLogoKind: String, Equatable, Sendable {
    case axiom
    case appleIntelligence
    case anthropic
    case openai
    case openrouter
    case venice
    case moonshot
    case zai
    case deepseek
    case alibaba
    case siliconflow
    case cohere
    case groq
    case xai
    case together
    case fireworks
    case cerebras
    case mistral
    case meta
    case lmstudio
    case ollama
    case unsloth

    var systemSymbolName: String? {
        switch self {
        case .appleIntelligence: return "apple.intelligence"
        default: return nil
        }
    }

    var imageName: String {
        switch self {
        case .axiom: return "AxiomLogo"
        case .appleIntelligence: return "apple.intelligence"
        case .anthropic: return "AnthropicLogo"
        case .openai: return "OpenAILogo"
        case .openrouter: return "OpenRouterLogo"
        case .venice: return "VeniceLogo"
        case .moonshot: return "MoonshotLogo"
        case .zai: return "ZAILogo"
        case .deepseek: return "DeepSeekLogo"
        case .alibaba: return "AlibabaLogo"
        case .siliconflow: return "SiliconFlowLogo"
        case .cohere: return "CohereLogo"
        case .groq: return "GroqLogo"
        case .xai: return "XAILogo"
        case .together: return "TogetherLogo"
        case .fireworks: return "FireworksLogo"
        case .cerebras: return "CerebrasLogo"
        case .mistral: return "MistralLogo"
        case .meta: return "MetaLogo"
        case .lmstudio: return "LMStudioLogo"
        case .ollama: return "OllamaLogo"
        case .unsloth: return "UnslothLogo"
        }
    }

    var accessibilityName: String {
        switch self {
        case .axiom: return String(localized: "Axiom")
        case .appleIntelligence: return String(localized: "Apple Intelligence")
        case .anthropic: return String(localized: "Anthropic")
        case .openai: return String(localized: "OpenAI")
        case .openrouter: return String(localized: "OpenRouter")
        case .venice: return String(localized: "Venice")
        case .moonshot: return String(localized: "Moonshot")
        case .zai: return String(localized: "Z.AI")
        case .deepseek: return String(localized: "DeepSeek")
        case .alibaba: return String(localized: "Alibaba Cloud")
        case .siliconflow: return String(localized: "SiliconFlow")
        case .cohere: return String(localized: "Cohere")
        case .groq: return String(localized: "Groq")
        case .xai: return String(localized: "xAI")
        case .together: return String(localized: "Together AI")
        case .fireworks: return String(localized: "Fireworks")
        case .cerebras: return String(localized: "Cerebras")
        case .mistral: return String(localized: "Mistral")
        case .meta: return String(localized: "Meta")
        case .lmstudio: return String(localized: "LM Studio")
        case .ollama: return String(localized: "Ollama")
        case .unsloth: return String(localized: "Unsloth")
        }
    }
}

/// HUD idle provider mark: template silhouette tinted pure white on the glass.
enum HUDIdleMark {
    static let usesTemplate = true
    static let tintHex = "FFFFFF"
    static let red = 1.0
    static let green = 1.0
    static let blue = 1.0
}

enum HUDIdleSlot: Equatable, Sendable {
    case waveform
    case logo(ProviderLogoKind)
}

enum HUDModelMenu {
    struct Item: Equatable, Sendable {
        var providerID: UUID
        var title: String
        var models: [ModelRow]
    }

    struct ModelRow: Equatable, Sendable {
        var id: String
        var title: String
        var enabled: Bool
    }

    struct Pick: Equatable, Sendable {
        var selection: ChatModelSelection
        var errorMessage: String?
    }

    static func selecting(
        providerID: UUID,
        modelID: String,
        in current: ChatModelSelection
    ) -> ChatModelSelection {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatModelSelection(
            chatID: providerID,
            chatModelID: providerID == ChatEndpointCatalog.onDeviceID ? "" : trimmed,
            visionID: current.visionID,
            visionModelID: current.visionModelID
        )
    }

    /// HUD logo menu only. A stored ChatGPT token is enough; this never starts
    /// OAuth and never returns the Settings Add sign-in copy.
    static func picking(
        providerID: UUID,
        modelID: String,
        in current: ChatModelSelection,
        secret _: String
    ) -> Pick {
        Pick(
            selection: selecting(providerID: providerID, modelID: modelID, in: current),
            errorMessage: nil
        )
    }

    static func isReady(
        _ endpoint: ChatEndpoint,
        secret: String,
        onDeviceReady: Bool = true
    ) -> Bool {
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            return onDeviceReady
        }
        if endpoint.kind == .chatgptSubscription {
            return ChatGPTAuth.parse(secret) != nil
        }
        let url = endpoint.completionsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            return false
        }
        if ChatEndpointCatalog.requiresAPIKey(endpoint) {
            return !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    static func logo(for endpoint: ChatEndpoint) -> ProviderLogoKind {
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            return .appleIntelligence
        }
        guard let presetID = resolvedPresetID(endpoint) else {
            return .axiom
        }
        return logo(forPreset: presetID)
    }

    static func logo(forPresetID id: String) -> ProviderLogoKind {
        logo(forPreset: id)
    }

    /// Waveform still wins while dictating. A debug logo override is display-only.
    static func idleSlot(
        dictating: Bool,
        override: ProviderLogoKind?,
        endpoint: ChatEndpoint
    ) -> HUDIdleSlot {
        if dictating {
            return .waveform
        }
        if let override {
            return .logo(override)
        }
        return .logo(logo(for: endpoint))
    }

    static func resolvedPresetID(_ endpoint: ChatEndpoint) -> String? {
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            return nil
        }
        if let presetID = endpoint.presetID,
           ChatEndpointCatalog.cloudPresets.contains(where: { $0.id == presetID })
        {
            return presetID
        }
        return ChatEndpointCatalog.cloudPresets.first(where: {
            ChatEndpointCatalog.matchesHost(endpoint.completionsURL, $0.baseURL)
        })?.id
    }

    static func items(
        endpoints: [ChatEndpoint],
        chatID: UUID?,
        chatModelID: String,
        secret: (UUID) -> String = { _ in "" },
        onDeviceReady: Bool = true
    ) -> [Item] {
        endpoints.compactMap { endpoint in
            guard isReady(endpoint, secret: secret(endpoint.id), onDeviceReady: onDeviceReady) else {
                return nil
            }
            return Item(
                providerID: endpoint.id,
                title: endpoint.name,
                models: modelRows(for: endpoint, chatID: chatID, chatModelID: chatModelID)
            )
        }
    }

    private static func logo(forPreset id: String) -> ProviderLogoKind {
        switch id {
        case "apple_foundation": return .appleIntelligence
        case "anthropic": return .anthropic
        case "openai", "chatgpt": return .openai
        case "openrouter": return .openrouter
        case "venice": return .venice
        case "moonshot": return .moonshot
        case "zai": return .zai
        case "deepseek": return .deepseek
        case "alibaba_cloud": return .alibaba
        case "siliconflow": return .siliconflow
        case "cohere": return .cohere
        case "groq": return .groq
        case "xai": return .xai
        case "together": return .together
        case "fireworks": return .fireworks
        case "cerebras": return .cerebras
        case "mistral": return .mistral
        case "meta": return .meta
        case "lmstudio": return .lmstudio
        case "ollama": return .ollama
        case "unsloth": return .unsloth
        default: return .axiom
        }
    }

    private static func modelRows(
        for endpoint: ChatEndpoint,
        chatID: UUID?,
        chatModelID: String
    ) -> [ModelRow] {
        if ChatEndpointCatalog.isOnDevice(endpoint) {
            return [ModelRow(id: "", title: endpoint.modelLabel, enabled: true)]
        }
        if !endpoint.availableModels.isEmpty {
            return endpoint.availableModels.map { ModelRow(id: $0, title: $0, enabled: true) }
        }
        let stored = storedModelID(for: endpoint, chatID: chatID, chatModelID: chatModelID)
        if stored.isEmpty {
            return [ModelRow(id: "", title: String(localized: "No models"), enabled: false)]
        }
        return [ModelRow(id: stored, title: stored, enabled: true)]
    }

    private static func storedModelID(
        for endpoint: ChatEndpoint,
        chatID: UUID?,
        chatModelID: String
    ) -> String {
        if endpoint.id == chatID {
            let chosen = chatModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chosen.isEmpty {
                return chosen
            }
        }
        return endpoint.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
