import Foundation
import Testing
@testable import Axiom

@Test func reasoningEffortBodiesMatchEachProvider() throws {
    let messages = [OutboundMessage(role: "user", text: "hi", imageJPEGs: [])]
    let off = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .off
    )
    let medium = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .medium
    )
    let low = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .low
    )
    let high = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .high
    )
    let minimal = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .minimal
    )

    let offCompletions = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ChatBody(request: off))
    ) as? [String: Any]
    #expect(offCompletions?["reasoning_effort"] as? String == "off")

    let onCompletions = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ChatBody(request: medium))
    ) as? [String: Any]
    #expect(onCompletions?["reasoning_effort"] as? String == "medium")
    #expect(
        (try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ChatBody(request: low))
        ) as? [String: Any])?["reasoning_effort"] as? String == "low"
    )
    #expect(
        (try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ChatBody(request: high))
        ) as? [String: Any])?["reasoning_effort"] as? String == "high"
    )
    #expect(
        (try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ChatBody(request: minimal))
        ) as? [String: Any])?["reasoning_effort"] as? String == "minimal"
    )

    let offResponses = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ResponsesBody(request: off))
    ) as? [String: Any]
    let offReasoning = try #require(offResponses?["reasoning"] as? [String: Any])
    #expect(offReasoning["effort"] as? String == "off")

    let onResponses = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ResponsesBody(request: medium))
    ) as? [String: Any]
    let reasoning = try #require(onResponses?["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "medium")

    let offAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: off))
    ) as? [String: Any]
    #expect(offAnthropic?["thinking"] == nil)

    let onAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: medium))
    ) as? [String: Any]
    let thinking = try #require(onAnthropic?["thinking"] as? [String: Any])
    #expect(thinking["type"] as? String == "enabled")
    #expect(thinking["budget_tokens"] as? Int == 8_192)
    #expect((onAnthropic?["max_tokens"] as? Int) ?? 0 > 8_192)

    let lowAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: low))
    ) as? [String: Any]
    #expect((lowAnthropic?["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 2_048)

    let highAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: high))
    ) as? [String: Any]
    #expect((highAnthropic?["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 16_384)
}

@Test func reasoningEffortDefaultsToOffAndPersists() {
    let suite = "aihud.tests.reasoning-effort.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(ReasoningEffort.load(from: defaults) == .off)
    #expect(ReasoningEffort.default == .off)
    ReasoningEffort.save(.high, to: defaults)
    #expect(ReasoningEffort.load(from: defaults) == .high)
    #expect(ReasoningEffort.off.openAIValue == "off")
    #expect(ReasoningEffort.medium.openAIValue == "medium")
    #expect(ReasoningEffort.low.openAIValue == "low")
    #expect(ReasoningEffort.high.openAIValue == "high")
    #expect(ReasoningEffort.minimal.openAIValue == "minimal")
    #expect(ReasoningEffort.off.anthropicBudgetTokens == nil)
    #expect(ReasoningEffort.minimal.anthropicBudgetTokens == 1_024)
}
