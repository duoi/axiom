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
    private static let fallbackURL = "https://api.openai.com/v1"
    private static let fallbackModel = "gpt-4o"

    var model: String
    var completionsURL: String
    var apiKey: String
    var devCleartextHost: String?

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
    }

    var allowedCleartextHosts: Set<String> {
        var hosts = EndpointResolver.loopbackHosts
        if let devCleartextHost {
            hosts.insert(devCleartextHost.lowercased())
        }
        return hosts
    }

    var resolvedURL: Result<URL, EndpointError> {
        EndpointResolver.completionsURL(
            configured: completionsURL,
            allowedCleartextHosts: allowedCleartextHosts
        )
    }

    var blockingMessage: String? {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return "Add an API key in Settings"
        }
        if case .failure = resolvedURL {
            return "Check the base URL in Settings"
        }
        return nil
    }

    func save() {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = completionsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmedModel
        completionsURL = trimmedURL
        UserDefaults.standard.set(trimmedModel, forKey: Self.modelKey)
        UserDefaults.standard.set(trimmedURL, forKey: Self.urlKey)
        try? KeychainStore.write(apiKey)
    }
}
