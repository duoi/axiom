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
            return .failure("The request failed.")
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

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.yield(.failure("The request failed."))
                        continuation.finish()
                        return
                    }
                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 64 * 1024 { break }
                        }
                        let message = SSEParser.errorMessage(from: data) ?? "The request failed (\(http.statusCode))."
                        continuation.yield(.failure(message))
                        continuation.finish()
                        return
                    }

                    var sawDone = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        switch AnthropicParser.parse(line: line) {
                        case .skip:
                            continue
                        case .token(let token):
                            continuation.yield(.token(token))
                        case .done:
                            sawDone = true
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        case .failure(let message):
                            continuation.yield(.failure(message))
                            continuation.finish()
                            return
                        }
                    }
                    if !sawDone {
                        continuation.yield(.failure("The response ended early."))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct AnthropicBody: Encodable {
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
    }

    struct Message: Encodable {
        var role: String
        var content: [Part]
    }

    var model: String
    var stream: Bool
    var maxTokens: Int
    var system: String?
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    init(request: ChatRequest) {
        model = request.model
        stream = true
        maxTokens = 4096
        var systemText = ""
        var outbound: [Message] = []
        for message in request.messages {
            if message.role == "system" {
                if systemText.isEmpty {
                    systemText = message.text
                } else {
                    systemText += "\n\n" + message.text
                }
                continue
            }
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
            if parts.isEmpty {
                parts.append(Part(type: "text", text: message.text, source: nil))
            }
            outbound.append(Message(role: message.role, content: parts))
        }
        system = systemText.isEmpty ? nil : systemText
        messages = outbound
    }
}
