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
    private static let modelKey = "endpoint.model"
    private static let urlKey = "endpoint.completionsURL"
    private static let visionModelKey = "endpoint.visionModel"
    private static let visionURLKey = "endpoint.visionURL"
    private static let hoverKey = "hud.keepHovering"
    private static let captureKey = "hud.captureTarget"
    private static let matteKey = HUDMaterial.matteKey
    private static let fallbackURL = "https://api.openai.com/v1"
    private static let fallbackModel = "gpt-4o"

    var model: String
    var completionsURL: String
    var apiKey: String
    var visionModel: String
    var visionURL: String
    var visionAPIKey: String
    var devCleartextHost: String?
    var keepHovering: Bool {
        didSet { UserDefaults.standard.set(keepHovering, forKey: Self.hoverKey) }
    }
    var captureTarget: CaptureTarget {
        didSet { UserDefaults.standard.set(captureTarget.rawValue, forKey: Self.captureKey) }
    }
    var usesMatte: Bool {
        didSet {
            UserDefaults.standard.set(usesMatte, forKey: Self.matteKey)
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
            HUDMaterial.saveAmount(clamped, to: .standard)
            onAppearanceChange()
        }
    }

    var glassPercent: Double {
        get { glassAmount * 100 }
        set { glassAmount = newValue / 100 }
    }
    var onAppearanceChange: () -> Void = {}

    init() {
        let defaults = UserDefaults.standard
        let dev = DevEndpointFile.bundled()
        devCleartextHost = dev.flatMap { URL(string: $0.completionsURL)?.host }
        let storedKey = KeychainStore.read()
        if storedKey == nil, let dev {
            model = dev.model
            completionsURL = dev.completionsURL
            apiKey = dev.apiKey
            try? KeychainStore.write(dev.apiKey)
            defaults.set(dev.model, forKey: Self.modelKey)
            defaults.set(dev.completionsURL, forKey: Self.urlKey)
        } else {
            model = defaults.string(forKey: Self.modelKey) ?? dev?.model ?? Self.fallbackModel
            completionsURL = defaults.string(forKey: Self.urlKey) ?? dev?.completionsURL ?? Self.fallbackURL
            apiKey = storedKey ?? ""
        }
        visionModel = defaults.string(forKey: Self.visionModelKey) ?? ""
        visionURL = defaults.string(forKey: Self.visionURLKey) ?? ""
        visionAPIKey = KeychainStore.read(account: KeychainStore.visionAccount) ?? ""
        if defaults.object(forKey: Self.hoverKey) == nil {
            keepHovering = true
        } else {
            keepHovering = defaults.bool(forKey: Self.hoverKey)
        }
        captureTarget = CaptureTarget(rawValue: defaults.string(forKey: Self.captureKey) ?? "") ?? .screen
        usesMatte = defaults.bool(forKey: Self.matteKey)
        glassAmount = HUDMaterial.loadAmount(from: defaults)
    }

    var allowedCleartextHosts: Set<String> {
        var hosts = EndpointResolver.loopbackHosts
        if let devCleartextHost {
            hosts.insert(devCleartextHost.lowercased())
        }
        for configured in [completionsURL, visionURL] {
            if let host = URL(string: configured)?.host?.lowercased() {
                hosts.insert(host)
            }
        }
        return hosts
    }

    func target(for messages: [OutboundMessage]) -> SendTarget {
        let hasImage = messages.contains { !$0.imageJPEGs.isEmpty }
        let chat = ServiceCredentials(url: completionsURL, model: model, apiKey: apiKey)
        let vision = ServiceCredentials(url: visionURL, model: visionModel, apiKey: visionAPIKey)
        if hasImage, ModelChoice.visionIsIncomplete(vision) {
            return .blocked("Finish the vision endpoint in Settings")
        }
        let chosen = ModelChoice.pick(chat: chat, vision: vision, hasImage: hasImage)
        let usingVision = hasImage && vision.isComplete
        switch EndpointResolver.completionsURL(configured: chosen.url, allowedCleartextHosts: allowedCleartextHosts) {
        case .success(let url):
            let modelID = chosen.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if modelID.isEmpty || chosen.apiKey.isEmpty {
                return .blocked(usingVision ? "Finish the vision endpoint in Settings" : "Add an API key in Settings")
            }
            return .ready(url: url, model: modelID, apiKey: chosen.apiKey)
        case .failure:
            return .blocked(usingVision ? "Check the vision URL in Settings" : "Check the base URL in Settings")
        }
    }

    var blockingMessage: String? {
        if case .blocked(let message) = target(for: []) {
            return message
        }
        return nil
    }

    func save() {
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        completionsURL = completionsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        visionModel = visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        visionURL = visionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(model, forKey: Self.modelKey)
        UserDefaults.standard.set(completionsURL, forKey: Self.urlKey)
        UserDefaults.standard.set(visionModel, forKey: Self.visionModelKey)
        UserDefaults.standard.set(visionURL, forKey: Self.visionURLKey)
        try? KeychainStore.write(apiKey)
        try? KeychainStore.write(visionAPIKey, account: KeychainStore.visionAccount)
    }
}

enum SendTarget: Equatable {
    case ready(url: URL, model: String, apiKey: String)
    case blocked(String)
}
