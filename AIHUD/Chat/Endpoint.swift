import Foundation

enum EndpointError: Equatable, Error {
    case empty
    case unsupportedScheme
    case fileURL
    case insecureHost
}

enum EndpointResolver {
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// `configured` is either a base URL or a full chat completions URL.
    /// Cleartext is allowed for loopback and for `allowedCleartextHosts`.
    static func completionsURL(
        configured: String,
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
        if path == "/chat/completions" || path.hasSuffix("/chat/completions") {
            components.path = path
            guard let url = components.url else { return .failure(.unsupportedScheme) }
            return .success(url)
        }

        components.path = path
        guard let base = components.url else { return .failure(.unsupportedScheme) }
        let joined = base
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        return .success(joined)
    }
}

enum RedirectPolicy {
    static func allows(originalHost: String, next: URL) -> Bool {
        guard let host = next.host, !host.isEmpty else { return false }
        return host.compare(originalHost, options: .caseInsensitive) == .orderedSame
    }
}
