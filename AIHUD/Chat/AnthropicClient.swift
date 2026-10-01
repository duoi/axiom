import Foundation

enum AnthropicParser {
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
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: request.url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(AnthropicBody(request: request))
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
                        switch AnthropicParser.parse(line: line) {
                        case .skip:
                            continue
                        case .token(let token):
                            sawToken = true
                            continuation.yield(.token(token))
                        case .done:
                            sawDone = true
                            for event in ToolCallAssembler.trailingEvents(wire: .anthropic, lines: lines) {
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
                        let assembled = ToolCallAssembler.anthropic(lines: lines)
                        if sawToken || !assembled.calls.isEmpty {
                            for event in ToolCallAssembler.trailingEvents(wire: .anthropic, lines: lines) {
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
        if let budget = request.reasoningEffort.anthropicBudgetTokens {
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
