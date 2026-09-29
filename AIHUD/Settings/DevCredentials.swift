import Foundation

enum DevCredentials {
    static let apiKeyName = "AXIOM_API_KEY"
    static let visionKeyName = "AXIOM_VISION_API_KEY"

    static var suppressesKeychain: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func envName(for account: String) -> String {
        if account == KeychainStore.visionAccount {
            return visionKeyName
        }
        let prefix = "api-key."
        if account.hasPrefix(prefix) {
            let id = account.dropFirst(prefix.count).replacingOccurrences(of: "-", with: "_")
            return "\(apiKeyName)_\(id)"
        }
        return apiKeyName
    }

    static func parseEnvFile(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                if value.hasPrefix("\""), value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'"), value.hasSuffix("'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    static func secret(
        account: String,
        environment: [String: String] = [:],
        fileValues: [String: String] = [:]
    ) -> String? {
        var merged = fileValues
        for (key, value) in environment {
            merged[key] = value
        }
        let name = envName(for: account)
        if let value = nonempty(merged[name]) {
            return value
        }
        if name != apiKeyName, let value = nonempty(merged[apiKeyName]) {
            return value
        }
        return nil
    }

    static func secret(account: String) -> String? {
        seedEnvFileIfMissing()
        return secret(account: account, environment: ProcessInfo.processInfo.environment, fileValues: loadFile())
    }

    static func seedEnvFileIfMissing() {
        guard suppressesKeychain, let root = repoRoot() else { return }
        let envURL = root.appendingPathComponent(".env")
        let fm = FileManager.default
        if fm.fileExists(atPath: envURL.path) {
            return
        }
        let jsonURL = root.appendingPathComponent("Config/dev-endpoint.json")
        guard let file = DevEndpointFile.load(from: jsonURL), !file.apiKey.isEmpty else {
            return
        }
        let line = "\(apiKeyName)=\(file.apiKey)\n"
        try? line.write(to: envURL, atomically: true, encoding: .utf8)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func loadFile() -> [String: String] {
        if let bundled = Bundle.main.url(forResource: "dev", withExtension: "env"),
           let text = try? String(contentsOf: bundled, encoding: .utf8)
        {
            return parseEnvFile(text)
        }
        guard let root = repoRoot() else { return [:] }
        let url = root.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parseEnvFile(text)
    }

    static func repoRoot(startingAt file: String = #filePath) -> URL? {
        var url = URL(fileURLWithPath: file).deletingLastPathComponent()
        let fm = FileManager.default
        while url.path != "/" {
            let project = url.appendingPathComponent("Axiom.xcodeproj")
            let git = url.appendingPathComponent(".git")
            if fm.fileExists(atPath: project.path) || fm.fileExists(atPath: git.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
