import Foundation

struct ToolCall: Equatable, Sendable {
    var id: String
    var name: String
    var arguments: String
}

struct AssembledTools: Equatable, Sendable {
    var text: String
    var calls: [ToolCall]
    var truncated: Bool
}

enum ToolCallAssembler {
    enum Wire: Equatable, Sendable {
        case completions
        case anthropic
        case responses
    }

    static func completions(lines: [String]) -> AssembledTools {
        assemble(wire: .completions, lines: lines)
    }

    static func anthropic(lines: [String]) -> AssembledTools {
        assemble(wire: .anthropic, lines: lines)
    }

    static func responses(lines: [String]) -> AssembledTools {
        assemble(wire: .responses, lines: lines)
    }

    static func trailingEvents(wire: Wire, lines: [String]) -> [ChatStreamEvent] {
        let assembled = assemble(wire: wire, lines: lines)
        if assembled.calls.isEmpty {
            return [.done]
        }
        return [.toolCalls(assembled.calls, truncated: assembled.truncated), .done]
    }

    private struct Draft {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private static func assemble(wire: Wire, lines: [String]) -> AssembledTools {
        var text = ""
        var drafts: [Int: Draft] = [:]
        var truncated = false
        for line in lines {
            guard let object = jsonObject(from: line) else { continue }
            switch wire {
            case .completions:
                absorbCompletions(object, text: &text, drafts: &drafts, truncated: &truncated)
            case .anthropic:
                absorbAnthropic(object, text: &text, drafts: &drafts, truncated: &truncated)
            case .responses:
                absorbResponses(object, text: &text, drafts: &drafts, truncated: &truncated)
            }
        }
        let calls = drafts.keys.sorted().compactMap { index -> ToolCall? in
            guard let draft = drafts[index], !draft.id.isEmpty else { return nil }
            return ToolCall(id: draft.id, name: draft.name, arguments: draft.arguments)
        }
        return AssembledTools(text: text, calls: calls, truncated: truncated)
    }

    private static func absorbCompletions(
        _ object: [String: Any],
        text: inout String,
        drafts: inout [Int: Draft],
        truncated: inout Bool
    ) {
        guard let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first
        else { return }
        if choice["finish_reason"] as? String == "length" {
            truncated = true
        }
        guard let delta = choice["delta"] as? [String: Any] else { return }
        if let content = delta["content"] as? String {
            text += content
        }
        guard let toolCalls = delta["tool_calls"] as? [[String: Any]] else { return }
        for call in toolCalls {
            let index = call["index"] as? Int ?? 0
            var draft = drafts[index] ?? Draft()
            if let id = call["id"] as? String, !id.isEmpty {
                draft.id = id
            }
            if let function = call["function"] as? [String: Any] {
                if let name = function["name"] as? String, !name.isEmpty {
                    draft.name = name
                }
                if let arguments = function["arguments"] as? String {
                    draft.arguments += arguments
                }
            }
            drafts[index] = draft
        }
    }

    private static func absorbAnthropic(
        _ object: [String: Any],
        text: inout String,
        drafts: inout [Int: Draft],
        truncated: inout Bool
    ) {
        let type = object["type"] as? String
        let index = object["index"] as? Int ?? 0
        if type == "content_block_start",
           let block = object["content_block"] as? [String: Any],
           block["type"] as? String == "tool_use"
        {
            var draft = drafts[index] ?? Draft()
            if let id = block["id"] as? String {
                draft.id = id
            }
            if let name = block["name"] as? String {
                draft.name = name
            }
            drafts[index] = draft
            return
        }
        if type == "content_block_delta",
           let delta = object["delta"] as? [String: Any]
        {
            if let chunk = delta["text"] as? String {
                text += chunk
            }
            if delta["type"] as? String == "input_json_delta",
               let partial = delta["partial_json"] as? String
            {
                var draft = drafts[index] ?? Draft()
                draft.arguments += partial
                drafts[index] = draft
            }
            return
        }
        if type == "message_delta",
           let delta = object["delta"] as? [String: Any],
           delta["stop_reason"] as? String == "max_tokens"
        {
            truncated = true
        }
    }

    private static func absorbResponses(
        _ object: [String: Any],
        text: inout String,
        drafts: inout [Int: Draft],
        truncated: inout Bool
    ) {
        let type = object["type"] as? String
        let index = object["output_index"] as? Int ?? 0
        if type == "response.incomplete" {
            truncated = true
        }
        if type == "response.output_text.delta", let delta = object["delta"] as? String {
            text += delta
        }
        if type == "response.output_item.added",
           let item = object["item"] as? [String: Any],
           item["type"] as? String == "function_call"
        {
            var draft = drafts[index] ?? Draft()
            if let id = item["call_id"] as? String, !id.isEmpty {
                draft.id = id
            } else if let id = item["id"] as? String, !id.isEmpty {
                draft.id = id
            }
            if let name = item["name"] as? String {
                draft.name = name
            }
            if let arguments = item["arguments"] as? String {
                draft.arguments = arguments
            }
            drafts[index] = draft
        }
        if type == "response.function_call_arguments.delta",
           let delta = object["delta"] as? String
        {
            var draft = drafts[index] ?? Draft()
            draft.arguments += delta
            drafts[index] = draft
        }
        if type == "response.function_call_arguments.done",
           let arguments = object["arguments"] as? String
        {
            var draft = drafts[index] ?? Draft()
            draft.arguments = arguments
            drafts[index] = draft
        }
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        var text = line
        if text.hasSuffix("\r") {
            text.removeLast()
        }
        guard text.hasPrefix("data:") else { return nil }
        let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
