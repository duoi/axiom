import Foundation

struct ChatRequest: Sendable {
    var url: URL
    var model: String
    var apiKey: String
    var messages: [OutboundMessage]
    var reasoningEffort: ReasoningEffort = ReasoningEffort.default
    var tools: [AgentToolDefinition] = []
}

enum ChatStreamEvent: Equatable, Sendable {
    case token(String)
    case toolCalls([ToolCall], truncated: Bool)
    case done
    case failure(String)
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let next = request.url,
              let original = task.originalRequest?.url,
              let originalHost = original.host,
              RedirectPolicy.allows(
                originalHost: originalHost,
                originalScheme: original.scheme,
                next: next
              )
        else {
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
        requestTimeout: TimeInterval = ChatTimeoutSettings.defaultSeconds
    ) -> (URLSession, RedirectGuard) {
        let timeout = ChatTimeoutSettings.clamp(requestTimeout)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = ChatTimeoutSettings.resourceTimeout(forRequest: timeout)
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let guardDelegate = RedirectGuard()
        let session = URLSession(configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
        return (session, guardDelegate)
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        SSEStream.run(session: session, wire: .completions, parse: SSEParser.parse(line:)) {
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            urlRequest.httpBody = try JSONEncoder().encode(ChatBody(request: request))
            return urlRequest
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
        var toolCalls: [ToolCall] = []
        var toolCallID: String? = nil

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

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            if toolCallID != nil {
                try container.encode(content, forKey: .content)
                try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
                return
            }
            if !toolCalls.isEmpty {
                if case .string(let value) = content, value.isEmpty {
                    try container.encodeNil(forKey: .content)
                } else {
                    try container.encode(content, forKey: .content)
                }
                try container.encode(toolCalls.map(EncodedToolCall.init), forKey: .toolCalls)
                return
            }
            try container.encode(content, forKey: .content)
        }
    }

    struct EncodedToolCall: Encodable {
        var id: String
        var type = "function"
        var function: Function

        struct Function: Encodable {
            var name: String
            var arguments: String
        }

        init(_ call: ToolCall) {
            id = call.id
            function = Function(name: call.name, arguments: call.arguments)
        }
    }

    var model: String
    var stream: Bool
    var messages: [Message]
    var reasoningEffort: String
    var tools: [AgentToolWire.OpenAI]?

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case messages
        case reasoningEffort = "reasoning_effort"
        case tools
    }

    init(request: ChatRequest) {
        model = request.model
        stream = true
        reasoningEffort = request.reasoningEffort.openAIValue
        tools = request.tools.isEmpty ? nil : AgentToolWire.openAI(request.tools)
        messages = request.messages.map { message in
            if message.toolCallID != nil {
                return Message(
                    role: message.role,
                    content: .string(message.text),
                    toolCallID: message.toolCallID
                )
            }
            if message.imageJPEGs.isEmpty {
                return Message(
                    role: message.role,
                    content: .string(message.text),
                    toolCalls: message.toolCalls
                )
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
            return Message(role: message.role, content: .parts(parts), toolCalls: message.toolCalls)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(stream, forKey: .stream)
        try container.encode(messages, forKey: .messages)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}
