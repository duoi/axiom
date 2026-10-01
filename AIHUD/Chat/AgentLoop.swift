import Foundation

struct ToolResult: Equatable, Sendable {
    var toolCallID: String
    var name: String
    var text: String
    var isError: Bool
}

struct AgentToolField: Equatable, Sendable {
    var name: String
    var description: String
    var required: Bool = true
}

struct AgentToolDefinition: Equatable, Sendable {
    var name: String
    var description: String
    var fields: [AgentToolField]
}

enum ExperimentalAgent {
    static let defaultsKey = "hud.experimentalAgent"

    static func load(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func save(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: defaultsKey)
    }
}

enum AgentLoop {
    static let stepCap = 8
    static let toolTimeout: TimeInterval = 30

    struct Turn: Equatable, Sendable {
        var text: String
        var calls: [ToolCall]
        var truncated: Bool
    }

    struct Outcome: Equatable, Sendable {
        var text: String
        var results: [ToolResult]
        var modelCalls: Int
        var stoppedForCap: Bool
    }

    static func run(
        sample: ([ToolResult]) -> Turn,
        execute: (ToolCall) -> ToolResult
    ) -> Outcome {
        var results: [ToolResult] = []
        var modelCalls = 0
        var text = ""
        while modelCalls < stepCap {
            let turn = sample(results)
            modelCalls += 1
            text = turn.text
            if turn.truncated {
                results.append(contentsOf: turn.calls.map(AgentTools.truncatedResult))
                continue
            }
            if turn.calls.isEmpty {
                return Outcome(text: text, results: results, modelCalls: modelCalls, stoppedForCap: false)
            }
            for call in turn.calls {
                results.append(execute(call))
            }
        }
        return Outcome(text: text, results: results, modelCalls: modelCalls, stoppedForCap: true)
    }
}

enum AgentTools {
    static let fetchName = "fetch_url"
    static let openName = "open_url"
    static let globName = "glob"
    static let grepName = "grep"
    static let readName = "read"

    static let definitions: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: fetchName,
            description: String(localized: "Fetch the text of a web page."),
            fields: [.init(name: "url", description: String(localized: "Absolute https URL. http is allowed only for a host this app already allows."))]
        ),
        AgentToolDefinition(
            name: openName,
            description: String(localized: "Open a URL in the browser. The user must confirm before it opens."),
            fields: [.init(name: "url", description: String(localized: "Absolute http or https URL."))]
        ),
        AgentToolDefinition(
            name: globName,
            description: String(localized: "List files in the selected folder whose path matches a glob."),
            fields: [.init(name: "pattern", description: String(localized: "Glob such as *.txt or docs/**/*.md. A pattern with no slash matches the file name."))]
        ),
        AgentToolDefinition(
            name: grepName,
            description: String(localized: "Search file contents in the selected folder for a literal string."),
            fields: [
                .init(name: "query", description: String(localized: "Literal text to find.")),
                .init(name: "pattern", description: String(localized: "Optional glob that limits which files are searched."), required: false),
            ]
        ),
        AgentToolDefinition(
            name: readName,
            description: String(localized: "Read a line window from one text file in the selected folder."),
            fields: [
                .init(name: "path", description: String(localized: "Path relative to the selected folder.")),
                .init(name: "offset", description: String(localized: "1-based line to start at."), required: false),
                .init(name: "limit", description: String(localized: "How many lines to return, up to 2000."), required: false),
            ]
        ),
    ]

    static func isFolderSearch(_ name: String) -> Bool {
        name == globName || name == grepName || name == readName
    }

    static func folderStatus(name: String, arguments: [String: String]) -> String {
        switch name {
        case globName:
            return String(localized: "Finding \(arguments["pattern"] ?? "")")
        case grepName:
            return String(localized: "Searching for \(arguments["query"] ?? "")")
        case readName:
            let path = arguments["path"] ?? ""
            let file = (path as NSString).lastPathComponent
            return String(localized: "Reading \(file.isEmpty ? path : file)")
        default:
            return name
        }
    }

    static func needsApproval(_ name: String) -> Bool {
        name == openName
    }

    static func unknownResult(_ call: ToolCall) -> ToolResult {
        ToolResult(
            toolCallID: call.id,
            name: call.name,
            text: String(localized: "Unknown tool \(call.name)."),
            isError: true
        )
    }

    static func truncatedResult(_ call: ToolCall) -> ToolResult {
        ToolResult(
            toolCallID: call.id,
            name: call.name,
            text: String(localized: "Tool call \"\(call.name)\" was not executed: the response hit the output limit, so its arguments may be truncated."),
            isError: true
        )
    }

    static func stringObject(from arguments: String) -> [String: String] {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var mapped: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                mapped[key] = string
            } else if let number = value as? NSNumber {
                mapped[key] = number.stringValue
            }
        }
        return mapped
    }
}

enum FetchURLPolicy {
    static let maxCharacters = 10_000
    static let edgeCharacters = 5_000

    static func url(from arguments: String) -> URL? {
        guard let raw = AgentTools.stringObject(from: arguments)["url"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return URL(string: raw)
    }

    static func allows(_ url: URL, allowedCleartextHosts: Set<String> = []) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = normalizedHost(url),
              !host.isEmpty
        else { return false }
        if scheme == "https" { return true }
        if scheme == "http" {
            let allowed = EndpointResolver.loopbackHosts.union(allowedCleartextHosts.map { $0.lowercased() })
            return allowed.contains(host)
        }
        return false
    }

    static func allowsOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = normalizedHost(url), !host.isEmpty else { return false }
        return true
    }

    static func elide(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        let head = String(text.prefix(edgeCharacters))
        let tail = String(text.suffix(edgeCharacters))
        let omitted = text.count - maxCharacters
        let notice = String(localized: "[Output too long. \(omitted) characters omitted.]")
        return "\(head)\n\n\(notice)\n\n\(tail)"
    }

    static func readableText(_ body: String, contentType: String?) -> String {
        let html = contentType?.localizedCaseInsensitiveContains("html") == true
            || body.range(of: "<html", options: .caseInsensitive) != nil
            || body.range(of: "<body", options: .caseInsensitive) != nil
        guard html else { return body }
        var text = body
        text = replacing(text, pattern: #"(?is)<script\b[^>]*>.*?</script>"#)
        text = replacing(text, pattern: #"(?is)<style\b[^>]*>.*?</style>"#)
        text = replacing(text, pattern: #"(?is)<[^>]+>"#)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = replacing(text, pattern: #"\s+"#, template: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ text: String, pattern: String, template: String = " ") -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    private static func normalizedHost(_ url: URL) -> String? {
        url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}

enum FetchURLTool {
    enum Load: Equatable, Sendable {
        case text(String)
        case failed(String)
    }

    static func load(url: URL, session: URLSession) async throws -> Load {
        var request = URLRequest(url: url)
        request.timeoutInterval = AgentLoop.toolTimeout
        request.setValue("text/plain, text/html;q=0.9", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(String(localized: "The fetch failed."))
            }
            if http.statusCode != 200 {
                return .failed(String(localized: "The fetch failed (\(http.statusCode))."))
            }
            let limited = data.prefix(1_000_000)
            let raw = String(decoding: limited, as: UTF8.self)
            let type = http.value(forHTTPHeaderField: "Content-Type")
            return .text(FetchURLPolicy.elide(FetchURLPolicy.readableText(raw, contentType: type)))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            return .failed(String(localized: "The fetch timed out."))
        } catch {
            return .failed(String(localized: "The fetch failed."))
        }
    }
}

enum AgentToolWire {
    struct Parameters: Encodable {
        var type = "object"
        var properties: [String: Field]
        var required: [String]

        struct Field: Encodable {
            var type = "string"
            var description: String
        }
    }

    struct OpenAI: Encodable {
        var type = "function"
        var function: Body

        struct Body: Encodable {
            var name: String
            var description: String
            var parameters: Parameters
        }
    }

    struct Anthropic: Encodable {
        var name: String
        var description: String
        var inputSchema: Parameters

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }
    }

    struct Responses: Encodable {
        var type = "function"
        var name: String
        var description: String
        var parameters: Parameters
    }

    static func openAI(_ tools: [AgentToolDefinition]) -> [OpenAI] {
        tools.map { tool in
            OpenAI(function: .init(name: tool.name, description: tool.description, parameters: parameters(tool)))
        }
    }

    static func anthropic(_ tools: [AgentToolDefinition]) -> [Anthropic] {
        tools.map { tool in
            Anthropic(name: tool.name, description: tool.description, inputSchema: parameters(tool))
        }
    }

    static func responses(_ tools: [AgentToolDefinition]) -> [Responses] {
        tools.map { tool in
            Responses(name: tool.name, description: tool.description, parameters: parameters(tool))
        }
    }

    private static func parameters(_ tool: AgentToolDefinition) -> Parameters {
        var properties: [String: Parameters.Field] = [:]
        var required: [String] = []
        for field in tool.fields {
            properties[field.name] = .init(description: field.description)
            if field.required { required.append(field.name) }
        }
        return Parameters(properties: properties, required: required)
    }
}

struct FolderHit: Equatable, Sendable {
    var text: String
    var isError: Bool
}

enum FolderGrant {
    static let defaultsKey = "hud.experimentalFolderBookmark"

    static func data(for url: URL) -> Data? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func url(from defaults: UserDefaults) -> URL? {
        guard let stored = defaults.data(forKey: defaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: stored,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let refreshed = Self.data(for: url) {
            defaults.set(refreshed, forKey: defaultsKey)
        }
        return url
    }

    static func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

enum FolderSearch {
    // ponytail: walk stops at 2,000 files and 1 MB each. Raise the caps if a real folder search misses hits.
    static let maxScan = 2_000
    static let maxGlobHits = 100
    static let maxGrepHits = 40
    static let maxReadLines = 2_000
    static let defaultReadLines = 200
    static let maxFileBytes = 1_000_000

    static func run(root: URL?, name: String, arguments: [String: String]) -> FolderHit {
        guard let root else {
            return FolderHit(text: String(localized: "No folder is selected. Choose one in Settings, Experimental."), isError: true)
        }
        switch name {
        case AgentTools.globName:
            return glob(root: root, pattern: arguments["pattern"] ?? "")
        case AgentTools.grepName:
            return grep(root: root, query: arguments["query"] ?? "", pattern: arguments["pattern"] ?? "")
        case AgentTools.readName:
            return read(
                root: root,
                path: arguments["path"] ?? "",
                offset: integer(arguments["offset"], default: 1),
                limit: integer(arguments["limit"], default: defaultReadLines)
            )
        default:
            return FolderHit(text: String(localized: "Unknown tool \(name)."), isError: true)
        }
    }

    private static func glob(root: URL, pattern: String) -> FolderHit {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return FolderHit(text: String(localized: "The tool arguments need a pattern string."), isError: true)
        }
        let walk = walk(root: root)
        let matched = walk.files.map(\.relative).filter { matches(relativePath: $0, pattern: pattern) }.sorted()
        if matched.isEmpty {
            let text = walk.stopped
                ? String(localized: "No files matched. No folder search past \(maxScan) files.")
                : String(localized: "No files matched.")
            return FolderHit(text: text, isError: false)
        }
        var lines = Array(matched.prefix(maxGlobHits))
        if matched.count > maxGlobHits {
            lines.insert(String(localized: "Showing \(maxGlobHits) of \(matched.count)."), at: 0)
        }
        if walk.stopped {
            lines.append(String(localized: "Stopped after \(maxScan) files."))
        }
        return FolderHit(text: FetchURLPolicy.elide(lines.joined(separator: "\n")), isError: false)
    }

    private static func grep(root: URL, query: String, pattern: String) -> FolderHit {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return FolderHit(text: String(localized: "The tool arguments need a query string."), isError: true)
        }
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let walk = walk(root: root)
        var hits: [String] = []
        for file in walk.files {
            if !pattern.isEmpty, !matches(relativePath: file.relative, pattern: pattern) { continue }
            guard let text = text(at: file.url) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                guard line.contains(query) else { continue }
                hits.append("\(file.relative):\(index + 1):\(clip(line))")
                if hits.count >= maxGrepHits { break }
            }
            if hits.count >= maxGrepHits { break }
        }
        if hits.isEmpty {
            let text = walk.stopped
                ? String(localized: "No matches. Stopped after \(maxScan) files.")
                : String(localized: "No matches.")
            return FolderHit(text: text, isError: false)
        }
        if hits.count >= maxGrepHits {
            hits.append(String(localized: "Stopped after \(maxGrepHits) matches."))
        } else if walk.stopped {
            hits.append(String(localized: "Stopped after \(maxScan) files."))
        }
        return FolderHit(text: FetchURLPolicy.elide(hits.joined(separator: "\n")), isError: false)
    }

    private static func read(root: URL, path: String, offset: Int, limit: Int) -> FolderHit {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return FolderHit(text: String(localized: "The tool arguments need a path string."), isError: true)
        }
        guard let located = locate(root: root, path: path) else {
            return FolderHit(text: String(localized: "That path is outside the selected folder."), isError: true)
        }
        let file = located.file
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
            return FolderHit(text: String(localized: "That file is not in the folder."), isError: true)
        }
        if isDirectory.boolValue {
            return FolderHit(text: String(localized: "That path is a folder."), isError: true)
        }
        guard let loaded = textFile(at: file) else {
            return FolderHit(text: String(localized: "That file is not text."), isError: true)
        }
        let lines = loaded.text.components(separatedBy: .newlines)
        let start = max(offset, 1)
        guard start <= lines.count else {
            return FolderHit(text: String(localized: "That line is past the end of the file."), isError: true)
        }
        let count = min(max(limit, 1), maxReadLines)
        let slice = lines.dropFirst(start - 1).prefix(count)
        let body = slice.enumerated().map { "\(start + $0.offset)|\($0.element)" }.joined(separator: "\n")
        let end = start + slice.count - 1
        let header = loaded.truncated
            ? String(localized: "\(located.display) lines \(start)-\(end) of \(lines.count). File is larger than \(maxFileBytes) bytes, so this is the start of it.")
            : String(localized: "\(located.display) lines \(start)-\(end) of \(lines.count)")
        return FolderHit(text: FetchURLPolicy.elide(header + "\n" + body), isError: false)
    }

    private static func integer(_ raw: String?, default defaultValue: Int) -> Int {
        guard let raw, let value = Int(raw) else { return defaultValue }
        return value
    }

    private struct ListedFile {
        var relative: String
        var url: URL
    }

    private struct Walk {
        var files: [ListedFile]
        var stopped: Bool
    }

    private static func walk(root: URL) -> Walk {
        let rootURL = lexicalRoot(root)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return Walk(files: [], stopped: false)
        }
        var files: [ListedFile] = []
        while let item = enumerator.nextObject() as? URL {
            let name = item.lastPathComponent
            if name == ".git" || name == "node_modules" {
                enumerator.skipDescendants()
                continue
            }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            guard values?.isRegularFile == true else { continue }
            guard contained(root: rootURL, candidate: item) != nil else { continue }
            files.append(ListedFile(relative: relative(item, root: rootURL), url: item))
            if files.count >= maxScan {
                return Walk(files: files, stopped: true)
            }
        }
        return Walk(files: files, stopped: false)
    }

    private static func locate(root: URL, path: String) -> (display: String, file: URL)? {
        let rootURL = lexicalRoot(root)
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : rootURL.appendingPathComponent(path)
        guard let resolved = contained(root: rootURL, candidate: candidate) else { return nil }
        return (relative(candidate, root: rootURL), resolved)
    }

    private static func contained(root: URL, candidate: URL) -> URL? {
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(root: root, url: resolved) else { return nil }
        return resolved
    }

    private static func isInside(root: URL, url: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let full = url.resolvingSymlinksInPath().standardizedFileURL.path
        if full == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return full.hasPrefix(prefix)
    }

    private static func lexicalRoot(_ root: URL) -> URL {
        root.standardizedFileURL
    }

    private static func relative(_ file: URL, root: URL) -> String {
        let rootPath = lexicalRoot(root).path
        let full = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard full.hasPrefix(prefix) else { return file.lastPathComponent }
        return String(full.dropFirst(prefix.count))
    }

    private static func matches(relativePath: String, pattern: String) -> Bool {
        if pattern == "*" || pattern == "**" || pattern == "**/*" { return true }
        if !pattern.contains("/") {
            return wholeMatch((relativePath as NSString).lastPathComponent, pattern: pattern)
        }
        return wholeMatch(relativePath, pattern: pattern)
    }

    private static func wholeMatch(_ text: String, pattern: String) -> Bool {
        text.range(of: anchoredRegex(pattern), options: .regularExpression) != nil
    }

    private static func anchoredRegex(_ pattern: String) -> String {
        var out = "^"
        let chars = Array(pattern)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "*", index + 1 < chars.count, chars[index + 1] == "*" {
                if index + 2 < chars.count, chars[index + 2] == "/" {
                    out += "(?:.*/)?"
                    index += 3
                    continue
                }
                out += ".*"
                index += 2
                continue
            }
            if character == "*" {
                out += "[^/]*"
                index += 1
                continue
            }
            if character == "?" {
                out += "[^/]"
                index += 1
                continue
            }
            out += NSRegularExpression.escapedPattern(for: String(character))
            index += 1
        }
        out += "$"
        return out
    }

    private static func text(at url: URL) -> String? {
        guard let loaded = textFile(at: url), !loaded.truncated else { return nil }
        return loaded.text
    }

    private static func textFile(at url: URL) -> (text: String, truncated: Bool)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let truncated = data.count > maxFileBytes
        let slice = data.prefix(maxFileBytes)
        if slice.contains(0) { return nil }
        return (String(decoding: slice, as: UTF8.self), truncated)
    }

    private static func clip(_ line: String) -> String {
        guard line.count > 200 else { return line }
        return String(line.prefix(200))
    }
}
