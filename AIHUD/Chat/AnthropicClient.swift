import Foundation

enum AnthropicParser {
    static func parse(line: String) -> SSEParser.Event {
        let object: [String: Any]
        switch SSEParser.line(line) {
        case .event(let event): return event
        case .object(let parsed): object = parsed
        }
        let type = object["type"] as? String
        if type == "message_stop" {
            return .done
        }
        if type == "error" {
            return .failure(String(localized: "The request failed."))
        }
        if type == "content_block_delta",
           let delta = object["delta"] as? [String: Any],
           let text = delta["text"] as? String,
           !text.isEmpty
        {
            return .token(text)
        }
        return .skip
    }
}

struct AnthropicClient: Sendable {
    let session: URLSession

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        SSEStream.run(session: session, wire: .anthropic, parse: AnthropicParser.parse(line:)) {
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            urlRequest.httpBody = try JSONEncoder().encode(AnthropicBody(request: request))
            return urlRequest
        }
    }
}

struct AnthropicBody: Encodable {
    struct Source: Encodable {
        var type = "base64"
        var mediaType = "image/jpeg"
        var data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    struct Part: Encodable {
        var type: String
        var text: String?
        var source: Source?
        var id: String? = nil
        var name: String? = nil
        var input: [String: String]? = nil
        var toolUseID: String? = nil
        var content: String? = nil
        var isError: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
            case id
            case name
            case input
            case content
            case toolUseID = "tool_use_id"
            case isError = "is_error"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(source, forKey: .source)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(input, forKey: .input)
            try container.encodeIfPresent(toolUseID, forKey: .toolUseID)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(isError, forKey: .isError)
        }
    }

    struct Message: Encodable {
        var role: String
        var content: [Part]
    }

    struct Thinking: Encodable {
        var type: String
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case type
            case budgetTokens = "budget_tokens"
        }
    }

    var model: String
    var stream: Bool
    var maxTokens: Int
    var system: String?
    var messages: [Message]
    var thinking: Thinking?
    var tools: [AgentToolWire.Anthropic]?

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case maxTokens = "max_tokens"
        case system
        case messages
        case thinking
        case tools
    }

    init(request: ChatRequest) {
        model = request.model
        stream = true
        // shortcut: no thinking with tools, because a tool step must echo the signed thinking block back
        // and ToolCallAssembler drops it. Keep thinking blocks there to allow both.
        if request.tools.isEmpty, let budget = request.reasoningEffort.anthropicBudgetTokens {
            thinking = Thinking(type: "enabled", budgetTokens: budget)
            maxTokens = max(4_096, budget + 4_096)
        } else {
            thinking = nil
            maxTokens = 4_096
        }
        tools = request.tools.isEmpty ? nil : AgentToolWire.anthropic(request.tools)
        var systemText = ""
        var outbound: [Message] = []
        var pendingResults: [Part] = []
        func flushResults() {
            if !pendingResults.isEmpty {
                outbound.append(Message(role: "user", content: pendingResults))
                pendingResults = []
            }
        }
        for message in request.messages {
            if message.role == "system" {
                flushResults()
                if systemText.isEmpty {
                    systemText = message.text
                } else {
                    systemText += "\n\n" + message.text
                }
                continue
            }
            if message.role == "tool" {
                pendingResults.append(
                    Part(
                        type: "tool_result",
                        toolUseID: message.toolCallID,
                        content: message.text,
                        isError: message.toolIsError ? true : nil
                    )
                )
                continue
            }
            flushResults()
            var parts: [Part] = []
            if !message.text.isEmpty {
                parts.append(Part(type: "text", text: message.text, source: nil))
            }
            for data in message.imageJPEGs {
                parts.append(
                    Part(
                        type: "image",
                        text: nil,
                        source: Source(data: data.base64EncodedString())
                    )
                )
            }
            for call in message.toolCalls {
                parts.append(
                    Part(
                        type: "tool_use",
                        id: call.id,
                        name: call.name,
                        input: AgentTools.stringObject(from: call.arguments)
                    )
                )
            }
            if parts.isEmpty {
                parts.append(Part(type: "text", text: message.text, source: nil))
            }
            outbound.append(Message(role: message.role, content: parts))
        }
        flushResults()
        system = systemText.isEmpty ? nil : systemText
        messages = outbound
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(stream, forKey: .stream)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}
