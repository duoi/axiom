import Foundation

enum SSEParser {
    enum Event: Equatable, Sendable {
        case token(String)
        case done
        case failure(String)
        case skip
    }

    static func parse(line: String) -> Event {
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
        if let message = errorMessage(in: object) {
            return .failure(message)
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
            return "The request failed."
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
