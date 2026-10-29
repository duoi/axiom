import Foundation

enum SSEParser {
    enum Event: Equatable, Sendable {
        case token(String)
        case done
        case failure(String)
        case skip
    }

    enum Line {
        case event(Event)
        case object([String: Any])
    }

    /// The part every wire shares: a `data:` line with a JSON object that is not an error.
    static func line(_ line: String) -> Line {
        var text = line
        if text.hasSuffix("\r") {
            text.removeLast()
        }
        if text.isEmpty || text.hasPrefix(":") {
            return .event(.skip)
        }
        guard text.hasPrefix("data:") else { return .event(.skip) }
        let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .event(.done)
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .event(.skip)
        }
        if let message = errorMessage(in: object) {
            return .event(.failure(message))
        }
        return .object(object)
    }

    static func parse(line: String) -> Event {
        let object: [String: Any]
        switch Self.line(line) {
        case .event(let event): return event
        case .object(let parsed): object = parsed
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty
        else {
            return .skip
        }
        return .token(content)
    }

    static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            return String(localized: "The request failed.")
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if let response = object["response"] as? [String: Any] {
            return errorMessage(in: response)
        }
        return nil
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return errorMessage(in: object)
    }
}

/// The streaming loop all three clients share. Each one only builds its request and parses its lines.
enum SSEStream {
    static func run(
        session: URLSession,
        wire: ToolCallAssembler.Wire,
        parse: @escaping @Sendable (String) -> SSEParser.Event,
        request makeRequest: @escaping @Sendable () async throws -> URLRequest
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            func fail(_ message: String) {
                continuation.yield(.failure(message))
                DebugHTTPTranscript.recordFailure(message)
                continuation.finish()
            }
            let task = Task {
                do {
                    let urlRequest = try await makeRequest()
                    DebugHTTPTranscript.recordRequest(urlRequest)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    DebugHTTPTranscript.recordStatus(response)
                    guard let http = response as? HTTPURLResponse else {
                        fail(String(localized: "The request failed."))
                        return
                    }
                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 64 * 1024 { break }
                        }
                        DebugHTTPTranscript.recordErrorBody(data)
                        fail(SSEParser.errorMessage(from: data) ?? String(localized: "The request failed (\(http.statusCode))."))
                        return
                    }

                    var sawDone = false
                    var sawToken = false
                    var lines: [String] = []
                    lineLoop: for try await line in bytes.lines {
                        try Task.checkCancellation()
                        DebugHTTPTranscript.recordLine(line)
                        lines.append(line)
                        switch parse(line) {
                        case .skip:
                            continue
                        case .token(let token):
                            sawToken = true
                            continuation.yield(.token(token))
                        case .done:
                            sawDone = true
                            break lineLoop
                        case .failure(let message):
                            fail(message)
                            return
                        }
                    }
                    let trailing = ToolCallAssembler.trailingEvents(wire: wire, lines: lines)
                    let hasToolCall = trailing.contains { if case .toolCalls = $0 { true } else { false } }
                    // A stream with no done, no text, and no tool call was cut off.
                    if !sawDone, !sawToken, !hasToolCall {
                        fail(String(localized: "The response ended early."))
                        return
                    }
                    for event in trailing {
                        continuation.yield(event)
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
                        fail(message)
                    } else {
                        fail(String(localized: "Sign in to ChatGPT in Settings"))
                    }
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
