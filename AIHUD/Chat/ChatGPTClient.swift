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
                return .failure("The request failed.")
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
                        switch ResponsesParser.parse(line: line) {
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
                } catch let error as ChatGPTAuthError {
                    if case .message(let message) = error {
                        continuation.yield(.failure(message))
                    } else {
                        continuation.yield(.failure("Sign in to ChatGPT in Settings"))
                    }
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

private struct ResponsesBody: Encodable {
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
        var role: String
        var content: [Content]
    }

    var model: String
    var input: [Input]
    var store: Bool
    var stream: Bool

    init(request: ChatRequest) {
        model = request.model
        store = false
        stream = true
        input = request.messages.map { message in
            var content: [Content] = []
            if !message.text.isEmpty {
                content.append(Content(type: "input_text", text: message.text, imageURL: nil))
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
                content.append(Content(type: "input_text", text: message.text, imageURL: nil))
            }
            return Input(role: message.role == "system" ? "developer" : message.role, content: content)
        }
    }
}
