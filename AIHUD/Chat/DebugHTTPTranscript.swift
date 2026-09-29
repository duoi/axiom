import Foundation

/// Live HTTP request/response dump for the Debug "Axiom transcript" window.
/// Secrets are redacted before anything is stored or shown.
enum DebugHTTPTranscript: Sendable {
    private final class Gate: @unchecked Sendable {
        let lock = NSLock()
        var armed = false
        var testStore: DebugTranscriptStore?
    }

    private static let gate = Gate()

    nonisolated static var isArmed: Bool {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        return gate.armed
    }

    nonisolated static func setArmed(_ value: Bool) {
        gate.lock.lock()
        gate.armed = value
        gate.lock.unlock()
    }

    /// Test hook: route appends into an isolated store instead of the shared one.
    @MainActor
    static func bindStoreForTests(_ store: DebugTranscriptStore?) {
        gate.lock.lock()
        gate.testStore = store
        gate.lock.unlock()
    }

    nonisolated static func formatRequest(_ request: URLRequest) -> String {
        DebugTranscriptFormatting.requestDump(request)
    }

    nonisolated static func recordRequest(_ request: URLRequest) {
        guard isArmed else { return }
        append(DebugTranscriptFormatting.requestDump(request) + "\n")
    }

    nonisolated static func recordStatus(_ response: URLResponse) {
        guard isArmed else { return }
        append(DebugTranscriptFormatting.statusDump(response) + "\n")
    }

    nonisolated static func recordLine(_ line: String) {
        guard isArmed else { return }
        append(DebugTranscriptRedaction.redactText(line) + "\n")
    }

    nonisolated static func recordErrorBody(_ data: Data) {
        guard isArmed else { return }
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        append(DebugTranscriptRedaction.redactJSONObjectText(text) + "\n")
    }

    nonisolated static func recordFinished() {
        guard isArmed else { return }
        append("-- stream end --\n\n")
    }

    nonisolated static func recordFailure(_ message: String) {
        guard isArmed else { return }
        append("-- failure: \(DebugTranscriptRedaction.redactText(message)) --\n\n")
    }

    private nonisolated static func append(_ chunk: String) {
        gate.lock.lock()
        let testStore = gate.testStore
        gate.lock.unlock()
        if let testStore {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    testStore.append(chunk)
                }
            } else {
                Task { @MainActor in
                    testStore.append(chunk)
                }
            }
            return
        }
        Task { @MainActor in
            DebugTranscriptStore.shared.append(chunk)
        }
    }
}

@MainActor
@Observable
final class DebugTranscriptStore {
    static let shared = DebugTranscriptStore()

    private(set) var text: String = ""
    var windowVisible = false

    private init() {}

    static func makeIsolatedForTests() -> DebugTranscriptStore {
        DebugTranscriptStore()
    }

    func append(_ chunk: String) {
        text += chunk
        if text.count > 400_000 {
            text = String(text.suffix(300_000))
        }
    }

    func clear() {
        text = ""
    }
}

enum DebugTranscriptRedaction: Sendable {
    static let placeholder = "[redacted]"

    private static let secretHeaders: Set<String> = [
        "authorization",
        "x-api-key",
        "api-key",
        "api_key",
        "cookie",
        "set-cookie",
        "proxy-authorization",
    ]

    private static let secretJSONKeys: Set<String> = [
        "api_key",
        "apikey",
        "api-key",
        "access_token",
        "refresh_token",
        "authorization",
        "x-api-key",
        "token",
        "password",
        "secret",
        "client_secret",
        "bearer",
    ]

    private static let secretQueryKeys: Set<String> = [
        "api_key",
        "apikey",
        "api-key",
        "access_token",
        "refresh_token",
        "token",
        "key",
        "authorization",
    ]

    static func isSecretHeader(_ name: String) -> Bool {
        secretHeaders.contains(name.lowercased())
    }

    static func isSecretJSONKey(_ key: String) -> Bool {
        secretJSONKeys.contains(key.lowercased())
    }

    static func redactHeaderValue(name: String, value: String) -> String {
        if isSecretHeader(name) { return placeholder }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") { return placeholder }
        return value
    }

    static func displayURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let items = components?.queryItems, !items.isEmpty {
            components?.queryItems = items.map { item in
                if secretQueryKeys.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: placeholder)
                }
                return item
            }
        }
        let host = url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        let query: String
        if let items = components?.queryItems, !items.isEmpty {
            query = "?" + items.map { item in
                let value = item.value ?? ""
                return "\(item.name)=\(value)"
            }.joined(separator: "&")
        } else {
            query = ""
        }
        return "\(host)\(path)\(query)"
    }

    static func redactText(_ text: String) -> String {
        redactJSONObjectText(text)
    }

    static func redactJSONObjectText(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return redactBearerLiterals(in: text)
        }
        let redacted = redactJSONValue(object)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let string = String(data: out, encoding: .utf8)
        else {
            return redactBearerLiterals(in: text)
        }
        return string
    }

    static func redactJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                if isSecretJSONKey(key) {
                    out[key] = placeholder
                } else if let string = nested as? String, looksLikeImageDataURL(string) {
                    out[key] = "[image omitted \(string.count) chars]"
                } else {
                    out[key] = redactJSONValue(nested)
                }
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map(redactJSONValue)
        }
        if let string = value as? String, looksLikeImageDataURL(string) {
            return "[image omitted \(string.count) chars]"
        }
        return value
    }

    private static func looksLikeImageDataURL(_ string: String) -> Bool {
        string.hasPrefix("data:image/") && string.count > 200
    }

    private static func redactBearerLiterals(in text: String) -> String {
        // Fallback for non-JSON SSE/error text that embeds Authorization-style tokens.
        var result = text
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9\-]+"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: placeholder
                )
            }
        }
        return result
    }
}

enum DebugTranscriptFormatting: Sendable {
    nonisolated static func requestDump(_ request: URLRequest) -> String {
        var lines: [String] = []
        lines.append("======== REQUEST ========")
        let method = request.httpMethod ?? "GET"
        if let url = request.url {
            lines.append("\(method) \(DebugTranscriptRedaction.displayURL(url))")
        } else {
            lines.append(method)
        }
        let headers = request.allHTTPHeaderFields ?? [:]
        for key in headers.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let value = headers[key] ?? ""
            let shown = DebugTranscriptRedaction.redactHeaderValue(name: key, value: value)
            lines.append("\(key): \(shown)")
        }
        if let body = request.httpBody, !body.isEmpty {
            lines.append("")
            if let text = String(data: body, encoding: .utf8) {
                lines.append(prettyBody(text))
            } else {
                lines.append("<\(body.count) binary bytes>")
            }
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func statusDump(_ response: URLResponse) -> String {
        var lines: [String] = ["======== RESPONSE ========"]
        if let http = response as? HTTPURLResponse {
            lines.append("HTTP \(http.statusCode)")
            if let url = http.url {
                lines.append(DebugTranscriptRedaction.displayURL(url))
            }
            for (key, value) in http.allHeaderFields {
                let name = "\(key)"
                let raw = "\(value)"
                let shown = DebugTranscriptRedaction.redactHeaderValue(name: name, value: raw)
                lines.append("\(name): \(shown)")
            }
        } else if let url = response.url {
            lines.append(DebugTranscriptRedaction.displayURL(url))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private nonisolated static func prettyBody(_ text: String) -> String {
        let redacted = DebugTranscriptRedaction.redactJSONObjectText(text)
        guard let data = redacted.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else {
            return redacted
        }
        return string
    }
}
