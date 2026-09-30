import Foundation

enum ModelList {
    static let failureMessage = "Could not list models."

    static func failureMessage(triedPath: String?, guidance: String? = nil) -> String {
        var parts: [String] = [failureMessage]
        if let raw = triedPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let path = sanitizedTriedPath(raw)
            if !path.isEmpty {
                parts.append("Tried \(path).")
            }
        }
        if let guidance = guidance?.trimmingCharacters(in: .whitespacesAndNewlines), !guidance.isEmpty {
            parts.append(guidance)
        }
        return parts.joined(separator: " ")
    }

    /// Path only. Drops query, fragment, user, and password.
    static func sanitizedTriedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            var path = url.path
            while path.count > 1 && path.hasSuffix("/") {
                path.removeLast()
            }
            return path.isEmpty ? "/" : path
        }
        var path = trimmed
        if let hash = path.firstIndex(of: "#") {
            path = String(path[..<hash])
        }
        if let query = path.firstIndex(of: "?") {
            path = String(path[..<query])
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func parseOpenAI(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]]
        else {
            return []
        }
        let ids = rows.compactMap { $0["id"] as? String }
        return sortByRecency(ids.filter { !shouldIgnoreOpenAI($0) })
    }

    static func parseAnthropic(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]]
        else {
            return []
        }
        let ids = rows.compactMap { $0["id"] as? String }
        return sortByRecency(ids.filter { !shouldIgnoreAnthropic($0) })
    }

    static func parseChatGPT(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["models"] as? [[String: Any]]
        else {
            return []
        }
        return rows.compactMap { row in
            guard let slug = row["slug"] as? String, !slug.isEmpty else { return nil }
            if let visibility = row["visibility"] as? String, visibility == "hide" {
                return nil
            }
            return slug
        }
    }

    static func selectModel(saved: String, models: [String]) -> String {
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if models.contains(trimmed) {
            return trimmed
        }
        if let first = models.first, !first.isEmpty {
            return first
        }
        return trimmed
    }

    static func isFailed(models: [String]) -> Bool {
        models.isEmpty
    }

    static func apply(models: [String], to endpoint: ChatEndpoint) -> ChatEndpoint {
        var next = endpoint
        guard !isFailed(models: models) else { return next }
        next.availableModels = models
        next.model = selectModel(saved: next.model, models: models)
        return next
    }

    static func shouldIgnoreOpenAI(_ id: String) -> Bool {
        shouldIgnoreCommonKeywords(id) || isNonChatModel(id) || isOldModel(id) || isDateSnapshot(id)
    }

    static func shouldIgnoreAnthropic(_ id: String) -> Bool {
        shouldIgnoreCommonKeywords(id) || isOldModel(id)
    }

    static func modelName(_ id: String) -> String {
        let dottedProviders: Set<String> = [
            "ai21", "amazon", "anthropic", "cohere", "deepseek", "google", "meta",
            "minimax", "mistral", "moonshot", "nvidia", "openai", "qwen",
            "stability", "twelvelabs", "writer", "xai", "zai"
        ]
        let name = id.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "~"))
            .lowercased()
            .split(separator: "/")
            .last
            .map(String.init) ?? id.lowercased()
        let segments = name.split(separator: ".").map(String.init)
        if let index = segments.firstIndex(where: { dottedProviders.contains($0) }),
           index < segments.count - 1
        {
            return segments[(index + 1)...].joined(separator: ".")
        }
        return name
    }

    static func shouldIgnoreCommonKeywords(_ id: String) -> Bool {
        let keywords = [
            "embed", "sora", "tts", "whisper", "dall-e", "audio", "image", "imagine",
            "veo", "lyria", "computer", "robotics", "realtime", "-live", "voice",
            "moderation", "codex", "transcribe", "translate", "search-api",
            "search-preview", "deep-research", "antigravity", "cyber", "daybreak"
        ]
        let lower = id.lowercased()
        return keywords.contains { lower.contains($0) }
    }

    static func isDateSnapshot(_ id: String) -> Bool {
        id.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            || id.range(of: #"-\d{8}$"#, options: .regularExpression) != nil
            || id.range(of: #"-20\d{2}$"#, options: .regularExpression) != nil
    }

    static func isNonChatModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let name = modelName(id)
        if name.range(of: #"^o\d"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gpt-4o-"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gpt-4\.1"#, options: .regularExpression) != nil { return true }
        if name.hasPrefix("ft:") || lower.hasPrefix("ft:") { return true }
        if name.range(of: #"^nano-banana"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^grok-(?:build|code-fast)"#, options: .regularExpression) != nil { return true }
        if name.contains("multi-agent") { return true }
        return false
    }

    static func isOldModel(_ id: String) -> Bool {
        let name = modelName(id)
        let dashed = name.replacingOccurrences(of: ".", with: "-")
        if name.range(of: #"^gpt-3\.5"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gpt-4"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gpt-5($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gpt-5\.[1-3]($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^(davinci|babbage|curie|ada)(-|$)"#, options: .regularExpression) != nil { return true }
        if dashed.range(of: #"^claude-(2|3|instant)"#, options: .regularExpression) != nil { return true }
        if dashed.range(of: #"^claude-opus-4($|-)"#, options: .regularExpression) != nil
            && dashed.range(of: #"^claude-opus-4-8($|-)"#, options: .regularExpression) == nil
        {
            return true
        }
        if dashed.range(of: #"^claude-sonnet-4($|-)"#, options: .regularExpression) != nil { return true }
        if dashed.range(of: #"^claude-haiku-4($|-)"#, options: .regularExpression) != nil
            && dashed.range(of: #"^claude-haiku-4-5($|-)"#, options: .regularExpression) == nil
        {
            return true
        }
        if name.range(of: #"^gemini-(1|2)(\.|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^gemini-3-"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^(open-)?mistral-(7b|nemo)(-|$)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^open-mixtral"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^mistral-large-(24|240|241|2502|2508)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^mistral-medium-(2505|2508|3[.-]1)($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^mistral-small-(3|2503|2506)($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^magistral-(small|medium)-\d{4}($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^devstral-"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^(pixtral|voxtral-mini-2507|mistral-saba|codestral-2501)"#, options: .regularExpression) != nil {
            return true
        }
        if name.range(of: #"^ministral-(3b|8b)-24"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^grok-[23]($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^grok-4($|-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^deepseek-(chat|reasoner)$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^deepseek-(v3|r1)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^(kimi-latest|kimi-thinking-preview|moonshot-v1)"#, options: .regularExpression) != nil {
            return true
        }
        if name.range(of: #"^kimi-k2($|-|[.p]5($|-))"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^glm-4"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^glm-5($|-|[.p]1($|-))"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^command-r(-plus)?(-|$)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^command(-light)?$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^c4ai-aya"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^llama-?3[.-]"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^llama-?4-"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^llama-guard"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^qwen-(3|max|plus|flash|turbo)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^qwen(2|3-)"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"^(qwq|qvq)-"#, options: .regularExpression) != nil { return true }
        return false
    }

    static func sortByRecency(_ models: [String]) -> [String] {
        let patterns = [
            #"(?:^|/)gpt-5\.6(?:-sol)?$"#,
            #"(?:^|/)gpt-5\.6-terra$"#,
            #"(?:^|/)gpt-5\.6-luna$"#,
            #"(?:^|/)gpt-5\.5$"#,
            #"(?:^|/)chat-latest$"#,
            #"(?:^|/)claude-fable-5[-.]1$"#,
            #"(?:^|/)claude-opus-5$"#,
            #"(?:^|/)claude-sonnet-(?:5|latest)$"#,
            #"(?:^|/)claude-fable-5$"#,
            #"(?:^|/)gpt-5\.4$"#,
            #"(?:^|/)gpt-5\.4-mini$"#,
            #"(?:^|/)gpt-5\.4-nano$"#,
            #"(?:^|/)claude-opus-4[-.]8$"#,
            #"(?:^|/)claude-haiku-4[-.]5(?:-\d{8})?$"#,
            #"(?:^|/)gemini-3\.8-flash$"#,
            #"(?:^|/)gemini-3\.7-flash$"#,
            #"(?:^|/)gemini-3\.6-flash$"#,
            #"(?:^|/)gemini-3\.5-flash-lite$"#,
            #"(?:^|/)gemini-3\.1-pro-preview$"#,
            #"(?:^|/)gemini-3\.5-flash$"#,
            #"(?:^|/)gemini-3\.1-flash-lite$"#,
            #"(?:^|/)grok-4\.6$"#,
            #"(?:^|/)grok-4\.5$"#,
            #"(?:^|/)grok-4\.3$"#,
            #"(?:^|/)mistral-medium-(?:3[-.]5|2604)"#,
            #"(?:^|/)(?:mistral-small-4|mistral-small-latest|mistral-small-2603)"#,
            #"(?:^|/)(?:mistral-large-3|mistral-large-2512)"#,
            #"(?:^|/)ministral-(?:3|14b-2512|8b-2512|3b-2512)"#,
            #"(?:^|/)kimi-k3$"#,
            #"(?:^|/)deepseek-v4-(?:pro|flash)$"#,
            #"(?:^|/)glm-5\.3$"#,
            #"(?:^|/)muse-spark-1\.3$"#
        ]
        func priority(_ model: String) -> Int {
            let normalized = modelName(model)
            if let index = patterns.firstIndex(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
                return index
            }
            return patterns.count
        }
        return models.sorted { lhs, rhs in
            let delta = priority(lhs) - priority(rhs)
            if delta != 0 { return delta < 0 }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}

struct ModelListResult: Equatable, Sendable {
    var models: [String]
    var triedURL: URL?

    var triedPath: String? {
        guard let triedURL else { return nil }
        return ModelList.sanitizedTriedPath(triedURL.absoluteString)
    }
}

struct ModelListClient: Sendable {
    var session: URLSession

    init(session: URLSession = URLSession(
        configuration: .ephemeral,
        delegate: RedirectGuard(),
        delegateQueue: nil
    )) {
        self.session = session
    }

    func list(endpoint: ChatEndpoint, secret: String, allowedCleartextHosts: Set<String>) async -> ModelListResult {
        switch endpoint.kind {
        case .onDevice:
            return ModelListResult(models: [], triedURL: nil)
        case .anthropic:
            return await listAnthropic(endpoint: endpoint, apiKey: secret, allowedCleartextHosts: allowedCleartextHosts)
        case .chatgptSubscription:
            return await listChatGPT(endpoint: endpoint, secret: secret, allowedCleartextHosts: allowedCleartextHosts)
        case .openaiCompatible:
            return await listOpenAI(endpoint: endpoint, apiKey: secret, allowedCleartextHosts: allowedCleartextHosts)
        }
    }

    private func listOpenAI(
        endpoint: ChatEndpoint,
        apiKey: String,
        allowedCleartextHosts: Set<String>
    ) async -> ModelListResult {
        guard case .success(let url) = EndpointResolver.modelsURL(
            configured: endpoint.completionsURL,
            allowedCleartextHosts: allowedCleartextHosts
        ) else {
            return ModelListResult(models: [], triedURL: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return await fetch(request, parse: ModelList.parseOpenAI)
    }

    private func listAnthropic(
        endpoint: ChatEndpoint,
        apiKey: String,
        allowedCleartextHosts: Set<String>
    ) async -> ModelListResult {
        guard case .success(let url) = EndpointResolver.modelsURL(
            configured: endpoint.completionsURL,
            allowedCleartextHosts: allowedCleartextHosts
        ) else {
            return ModelListResult(models: [], triedURL: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return await fetch(request, parse: ModelList.parseAnthropic)
    }

    private func listChatGPT(
        endpoint: ChatEndpoint,
        secret: String,
        allowedCleartextHosts: Set<String>
    ) async -> ModelListResult {
        guard let credential = ChatGPTAuth.parse(secret), !credential.access.isEmpty else {
            return ModelListResult(models: [], triedURL: nil)
        }
        guard case .success(let base) = EndpointResolver.modelsURL(
            configured: endpoint.completionsURL.isEmpty ? ChatGPTAuth.apiBase : endpoint.completionsURL,
            allowedCleartextHosts: allowedCleartextHosts
        ) else {
            return ModelListResult(models: [], triedURL: nil)
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "client_version", value: ChatGPTAuth.clientVersion)]
        guard let url = components?.url else {
            return ModelListResult(models: [], triedURL: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        ChatGPTAuth.applyCodexHeaders(&request, accessToken: credential.access, accountId: credential.accountId)
        return await fetch(request, parse: ModelList.parseChatGPT)
    }

    private func fetch(_ request: URLRequest, parse: @escaping (Data) -> [String]) async -> ModelListResult {
        let tried = request.url
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ModelListResult(models: [], triedURL: tried)
            }
            return ModelListResult(models: parse(data), triedURL: tried)
        } catch {
            return ModelListResult(models: [], triedURL: tried)
        }
    }
}
