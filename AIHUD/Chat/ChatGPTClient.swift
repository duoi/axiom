import Foundation

enum ResponsesParser {
    static func parse(line: String) -> SSEParser.Event {
        let object: [String: Any]
        switch SSEParser.line(line) {
        case .event(let event): return event
        case .object(let parsed): object = parsed
        }
        let type = object["type"] as? String
        if type == "response.completed" || type == "response.incomplete" || type == "response.failed" {
            if type == "response.failed" {
                if let response = object["response"] as? [String: Any],
                   let message = SSEParser.errorMessage(in: response)
                {
                    return .failure(message)
                }
                return .failure(String(localized: "The request failed."))
            }
            return .done
        }
        if type == "response.output_text.delta",
           let delta = object["delta"] as? String,
           !delta.isEmpty
        {
            return .token(delta)
        }
        return .skip
    }
}

struct ChatGPTClient: Sendable {
    let session: URLSession

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        SSEStream.run(session: session, wire: .responses, parse: ResponsesParser.parse(line:)) {
            let credential = try await ChatGPTAuth.freshCredential(request.apiKey)
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            ChatGPTAuth.applyCodexHeaders(
                &urlRequest,
                accessToken: credential.access,
                accountId: credential.accountId
            )
            urlRequest.httpBody = try JSONEncoder().encode(ResponsesBody(request: request))
            return urlRequest
        }
    }
}

struct ResponsesBody: Encodable {
    struct Content: Encodable {
        var type: String
        var text: String?
        var imageURL: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
    }

    struct Input: Encodable {
        var role: String? = nil
        var content: [Content]? = nil
        var type: String? = nil
        var callID: String? = nil
        var name: String? = nil
        var arguments: String? = nil
        var output: String? = nil

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case type
            case name
            case arguments
            case output
            case callID = "call_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let type {
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(callID, forKey: .callID)
                try container.encodeIfPresent(name, forKey: .name)
                try container.encodeIfPresent(arguments, forKey: .arguments)
                try container.encodeIfPresent(output, forKey: .output)
                return
            }
            try container.encodeIfPresent(role, forKey: .role)
            try container.encodeIfPresent(content, forKey: .content)
        }
    }

    struct Reasoning: Encodable {
        var effort: String
    }

    var model: String
    var input: [Input]
    var store: Bool
    var stream: Bool
    var reasoning: Reasoning
    var tools: [AgentToolWire.Responses]?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case store
        case stream
        case reasoning
        case tools
    }

    init(request: ChatRequest) {
        model = request.model
        store = false
        stream = true
        reasoning = Reasoning(effort: request.reasoningEffort.openAIValue)
        tools = request.tools.isEmpty ? nil : AgentToolWire.responses(request.tools)
        var items: [Input] = []
        for message in request.messages {
            if message.role == "tool" {
                items.append(
                    Input(
                        type: "function_call_output",
                        callID: message.toolCallID,
                        output: message.text
                    )
                )
                continue
            }
            if !message.toolCalls.isEmpty {
                if !message.text.isEmpty || !message.imageJPEGs.isEmpty {
                    items.append(Self.inputItem(message))
                }
                for call in message.toolCalls {
                    items.append(
                        Input(
                            type: "function_call",
                            callID: call.id,
                            name: call.name,
                            arguments: call.arguments
                        )
                    )
                }
                continue
            }
            items.append(Self.inputItem(message))
        }
        input = items
    }

    private static func inputItem(_ message: OutboundMessage) -> Input {
        let textType = message.role == "assistant" ? "output_text" : "input_text"
        var content: [Content] = []
        if !message.text.isEmpty {
            content.append(Content(type: textType, text: message.text, imageURL: nil))
        }
        for data in message.imageJPEGs {
            content.append(
                Content(
                    type: "input_image",
                    text: nil,
                    imageURL: "data:image/jpeg;base64,\(data.base64EncodedString())"
                )
            )
        }
        if content.isEmpty {
            content.append(Content(type: textType, text: message.text, imageURL: nil))
        }
        let role = message.role == "system" ? "developer" : message.role
        return Input(role: role, content: content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(tools, forKey: .tools)
    }
}
