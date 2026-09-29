import CryptoKit
import Foundation
import Network

enum ChatGPTAuth {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let callbackPort: UInt16 = 1455
    static let apiBase = "https://chatgpt.com/backend-api/codex"
    static let clientVersion = "0.145.0"
    static let originator = "codex_cli_rs"
    static let scope = "openid profile email offline_access"
    private static let refreshSkew: TimeInterval = 2 * 60

    struct Credential: Equatable, Sendable {
        var refresh: String
        var access: String
        var expires: Double
        var accountId: String?

        var expiresDate: Date {
            Date(timeIntervalSince1970: expires > 1_000_000_000_000 ? expires / 1000 : expires)
        }
    }

    struct ConnectSession: Equatable, Sendable {
        var url: URL
        var verifier: String
        var state: String
    }

    static func serialize(_ credential: Credential) -> String {
        var object: [String: Any] = [
            "type": "oauth",
            "refresh": credential.refresh,
            "access": credential.access,
            "expires": credential.expires
        ]
        if let accountId = credential.accountId {
            object["accountId"] = accountId
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }

    static func parse(_ value: String) -> Credential? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "oauth",
              let refresh = object["refresh"] as? String, !refresh.isEmpty,
              let access = object["access"] as? String,
              let expiresValue = object["expires"]
        else {
            return nil
        }
        let expires: Double
        if let value = expiresValue as? Double {
            expires = value
        } else if let value = expiresValue as? Int {
            expires = Double(value)
        } else if let value = expiresValue as? NSNumber {
            expires = value.doubleValue
        } else {
            return nil
        }
        let accountId = object["accountId"] as? String
        return Credential(refresh: refresh, access: access, expires: expires, accountId: accountId)
    }

    static func isFresh(_ credential: Credential, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard !credential.access.isEmpty else { return false }
        let expires = credential.expires > 1_000_000_000_000 ? credential.expires / 1000 : credential.expires
        return expires - refreshSkew > now
    }

    static func startConnect() -> ConnectSession {
        let verifier = randomToken(32)
        let state = randomToken(16)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: originator)
        ]
        return ConnectSession(url: components.url!, verifier: verifier, state: state)
    }

    static func parseAuthorizationInput(_ input: String) throws -> (code: String, state: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChatGPTAuthError.message("Paste the authorization code to continue.")
        }
        if let url = URL(string: trimmed), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty
            {
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                return (code, state)
            }
        }
        if let hash = trimmed.firstIndex(of: "#") {
            let code = trimmed[..<hash].trimmingCharacters(in: .whitespacesAndNewlines)
            let state = trimmed[trimmed.index(after: hash)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else {
                throw ChatGPTAuthError.message("Paste the authorization code to continue.")
            }
            return (code, state.isEmpty ? nil : state)
        }
        return (trimmed, nil)
    }

    static func assertState(session: ConnectSession, parsedState: String?) throws {
        if let parsedState, parsedState != session.state {
            throw ChatGPTAuthError.message("This sign-in expired. Try connecting again.")
        }
    }

    static func exchangeCode(code: String, verifier: String) async throws -> Credential {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ], fallback: "Could not connect ChatGPT subscription.")
    }

    static func refresh(_ credential: Credential) async throws -> Credential {
        var next = try await tokenRequest([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": credential.refresh
        ], fallback: "Could not refresh ChatGPT subscription.", previous: credential)
        if next.accountId == nil {
            next.accountId = credential.accountId
        }
        return next
    }

    static func freshCredential(_ secret: String) async throws -> Credential {
        guard let credential = parse(secret) else {
            throw ChatGPTAuthError.message("Sign in to ChatGPT in Settings")
        }
        if isFresh(credential) {
            return credential
        }
        return try await refresh(credential)
    }

    static func applyCodexHeaders(_ request: inout URLRequest, accessToken: String, accountId: String?) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(originator, forHTTPHeaderField: "originator")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue(originator, forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        if let residency = residency(from: accessToken) {
            request.setValue(residency, forHTTPHeaderField: "x-openai-internal-codex-residency")
        }
        request.setValue(UUID().uuidString, forHTTPHeaderField: "session_id")
    }

    static func accountID(from jwt: String) -> String? {
        guard let payload = decodeJWT(jwt) else { return nil }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
           let nested = auth["chatgpt_account_id"] as? String, !nested.isEmpty
        {
            return nested
        }
        if let direct = payload["chatgpt_account_id"] as? String, !direct.isEmpty {
            return direct
        }
        if let organizations = payload["organizations"] as? [[String: Any]],
           let id = organizations.first?["id"] as? String, !id.isEmpty
        {
            return id
        }
        return nil
    }

    static func residency(from jwt: String) -> String? {
        guard let payload = decodeJWT(jwt) else { return nil }
        let nested = (payload["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_compute_residency"] as? String
        let residency = nested ?? (payload["chatgpt_compute_residency"] as? String)
        guard let residency, !residency.isEmpty, residency != "no_constraint" else {
            return nil
        }
        return residency
    }

    private static func tokenRequest(
        _ fields: [String: String],
        fallback: String,
        previous: Credential? = nil
    ) async throws -> Credential {
        guard let url = URL(string: tokenURL) else {
            throw ChatGPTAuthError.message(fallback)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status < 400, let access = object["access_token"] as? String, !access.isEmpty else {
            throw ChatGPTAuthError.message(fallback)
        }
        let expiresIn = (object["expires_in"] as? Double) ?? (object["expires_in"] as? Int).map(Double.init) ?? 3600
        let refresh = (object["refresh_token"] as? String) ?? previous?.refresh ?? access
        let accountId = accountID(from: object["id_token"] as? String ?? "")
            ?? accountID(from: access)
            ?? (object["account_id"] as? String)
            ?? previous?.accountId
        return Credential(
            refresh: refresh,
            access: access,
            expires: Date().timeIntervalSince1970 + expiresIn,
            accountId: accountId
        )
    }

    private static func decodeJWT(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func randomToken(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return base64URL(Data(buffer))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+:/?&=%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum ChatGPTAuthError: Error, Equatable {
    case message(String)
}

final class OAuthCallbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?

    func listen() async throws -> URL {
        if listener != nil {
            throw ChatGPTAuthError.message("Sign-in is already waiting.")
        }
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: ChatGPTAuth.callbackPort)!)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.finish(.failure(ChatGPTAuthError.message("Could not listen for ChatGPT sign-in. Paste the redirect URL.")))
                }
            }
            listener.start(queue: .main)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let path = text.split(separator: "\r\n").first.map(String.init) ?? ""
            let target = path.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            if let url = URL(string: "http://localhost:\(ChatGPTAuth.callbackPort)\(target)"),
               url.path == "/auth/callback"
            {
                self.reply(connection, status: 200, body: "<html><body>You can close this window and return to Axiom.</body></html>")
                self.finish(.success(url))
            } else {
                self.reply(connection, status: 404, body: "Not found")
            }
        }
    }

    private func reply(_ connection: NWConnection, status: Int, body: String) {
        let payload = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status) OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        \r
        """
        var data = Data(header.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<URL, Error>) {
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}
