import Foundation

struct ChatRequest: Sendable {
    var url: URL
    var model: String
    var apiKey: String
    var messages: [OutboundMessage]
    var reasoningEffort: ReasoningEffort = .off
}

enum ChatStreamEvent: Equatable, Sendable {
    case token(String)
    case done
    case failure(String)
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let originalHost: String

    init(originalHost: String) {
        self.originalHost = originalHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let next = request.url, RedirectPolicy.allows(originalHost: originalHost, next: next) else {
            return nil
        }
        return request
    }
}

struct ChatClient: Sendable {
    let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    static func makeSession(
        host: String,
        requestTimeout: TimeInterval = ChatTimeoutSettings.defaultSeconds
    ) -> (URLSession, RedirectGuard) {
        let timeout = ChatTimeoutSettings.clamp(requestTimeout)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = ChatTimeoutSettings.resourceTimeout(forRequest: timeout)
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let guardDelegate = RedirectGuard(originalHost: host)
        let session = URLSession(configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
        return (session, guardDelegate)
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: request.url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(ChatBody(request: request))
                    DebugHTTPTranscript.recordRequest(urlRequest)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    DebugHTTPTranscript.recordStatus(response)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.failure("The request failed."))
                        DebugHTTPTranscript.recordFailure("The request failed.")
                        continuation.finish()
                        return
                    }
                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 64 * 1024 { break }
                        }
                        DebugHTTPTranscript.recordErrorBody(data)
                        let message = SSEParser.errorMessage(from: data) ?? "The request failed (\(http.statusCode))."
                        continuation.yield(.failure(message))
                        DebugHTTPTranscript.recordFailure(message)
                        continuation.finish()
                        return
                    }

                    var sawDone = false
                    var sawToken = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        DebugHTTPTranscript.recordLine(line)
                        switch SSEParser.parse(line: line) {
                        case .skip:
                            continue
                        case .token(let token):
                            sawToken = true
                            continuation.yield(.token(token))
                        case .done:
                            sawDone = true
                            continuation.yield(.done)
                            DebugHTTPTranscript.recordFinished()
                            continuation.finish()
                            return
                        case .failure(let message):
                            continuation.yield(.failure(message))
                            DebugHTTPTranscript.recordFailure(message)
                            continuation.finish()
                            return
                        }
                    }
                    if !sawDone {
                        if sawToken {
                            continuation.yield(.done)
                        } else {
                            continuation.yield(.failure("The response ended early."))
                            DebugHTTPTranscript.recordFailure("The response ended early.")
                            continuation.finish()
                            return
                        }
                    }
                    DebugHTTPTranscript.recordFinished()
                    continuation.finish()
                } catch is CancellationError {
                    DebugHTTPTranscript.recordFinished()
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    DebugHTTPTranscript.recordFinished()
                    continuation.finish()
                } catch {
                    DebugHTTPTranscript.recordFailure(error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct ChatBody: Encodable {
    struct ImageURL: Encodable {
        var url: String
    }

    struct Part: Encodable {
        var type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(imageURL, forKey: .imageURL)
        }
    }

    struct Message: Encodable {
        var role: String
        var content: Content

        enum Content: Encodable {
            case string(String)
            case parts([Part])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let value):
                    try container.encode(value)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }
    }

    var model: String
    var stream: Bool
    var messages: [Message]
    var reasoningEffort: String

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case messages
        case reasoningEffort = "reasoning_effort"
    }

    init(request: ChatRequest) {
        model = request.model
        stream = true
        reasoningEffort = request.reasoningEffort.openAIValue
        messages = request.messages.map { message in
            if message.imageJPEGs.isEmpty {
                return Message(role: message.role, content: .string(message.text))
            }
            var parts = [Part(type: "text", text: message.text, imageURL: nil)]
            for data in message.imageJPEGs {
                let encoded = data.base64EncodedString()
                parts.append(
                    Part(
                        type: "image_url",
                        text: nil,
                        imageURL: ImageURL(url: "data:image/jpeg;base64,\(encoded)")
                    )
                )
            }
            return Message(role: message.role, content: .parts(parts))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(stream, forKey: .stream)
        try container.encode(messages, forKey: .messages)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
    }
}
