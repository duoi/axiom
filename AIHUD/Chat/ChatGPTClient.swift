import Foundation

enum ResponsesParser {
    static func parse(line: String) -> SSEParser.Event {
        var text = line
        if text.hasSuffix("\r") {
            text.removeLast()
        }
        if text.isEmpty || text.hasPrefix(":") {
            return .skip
        }
        guard text.hasPrefix("data:") else { return .skip }
        let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .skip
        }
        if let message = SSEParser.errorMessage(in: object) {
            return .failure(message)
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
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
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
                    DebugHTTPTranscript.recordRequest(urlRequest)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    DebugHTTPTranscript.recordStatus(response)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.failure(String(localized: "The request failed.")))
                        DebugHTTPTranscript.recordFailure(String(localized: "The request failed."))
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
                        let message = SSEParser.errorMessage(from: data) ?? String(localized: "The request failed (\(http.statusCode)).")
                        continuation.yield(.failure(message))
                        DebugHTTPTranscript.recordFailure(message)
                        continuation.finish()
                        return
                    }

                    var sawDone = false
                    var sawToken = false
                    var lines: [String] = []
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        DebugHTTPTranscript.recordLine(line)
                        lines.append(line)
                        switch ResponsesParser.parse(line: line) {
                        case .skip:
                            continue
                        case .token(let token):
                            sawToken = true
                            continuation.yield(.token(token))
                        case .done:
                            sawDone = true
                            for event in ToolCallAssembler.trailingEvents(wire: .responses, lines: lines) {
                                continuation.yield(event)
                            }
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
                        let assembled = ToolCallAssembler.responses(lines: lines)
                        if sawToken || !assembled.calls.isEmpty {
                            for event in ToolCallAssembler.trailingEvents(wire: .responses, lines: lines) {
                                continuation.yield(event)
                            }
                        } else {
                            continuation.yield(.failure(String(localized: "The response ended early.")))
                            DebugHTTPTranscript.recordFailure(String(localized: "The response ended early."))
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
                } catch let error as ChatGPTAuthError {
                    if case .message(let message) = error {
                        continuation.yield(.failure(message))
                        DebugHTTPTranscript.recordFailure(message)
                    } else {
                        continuation.yield(.failure(String(localized: "Sign in to ChatGPT in Settings")))
                        DebugHTTPTranscript.recordFailure(String(localized: "Sign in to ChatGPT in Settings"))
                    }
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
