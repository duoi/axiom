import Foundation
import Testing
@testable import Axiom

@Test func reasoningEffortBodiesMatchEachProvider() throws {
    let messages = [OutboundMessage(role: "user", text: "hi", imageJPEGs: [])]
    let none = ChatRequest(
        url: URL(string: "https://example.com/v1")!,
        model: "m",
        apiKey: "",
        messages: messages,
        reasoningEffort: .none
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

    let noneCompletions = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ChatBody(request: none))
    ) as? [String: Any]
    #expect(noneCompletions?["reasoning_effort"] as? String == "none")

    let mediumCompletions = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ChatBody(request: medium))
    ) as? [String: Any]
    #expect(mediumCompletions?["reasoning_effort"] as? String == "medium")
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

    let noneResponses = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ResponsesBody(request: none))
    ) as? [String: Any]
    let noneReasoning = try #require(noneResponses?["reasoning"] as? [String: Any])
    #expect(noneReasoning["effort"] as? String == "none")

    let mediumResponses = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ResponsesBody(request: medium))
    ) as? [String: Any]
    let reasoning = try #require(mediumResponses?["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "medium")

    let noneAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: none))
    ) as? [String: Any]
    #expect(noneAnthropic?["thinking"] == nil)

    let mediumAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: medium))
    ) as? [String: Any]
    let thinking = try #require(mediumAnthropic?["thinking"] as? [String: Any])
    #expect(thinking["type"] as? String == "enabled")
    #expect(thinking["budget_tokens"] as? Int == 8_192)
    #expect((mediumAnthropic?["max_tokens"] as? Int) ?? 0 > 8_192)

    let lowAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: low))
    ) as? [String: Any]
    #expect((lowAnthropic?["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 2_048)

    let highAnthropic = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AnthropicBody(request: high))
    ) as? [String: Any]
    #expect((highAnthropic?["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 16_384)
}

@Test func reasoningEffortDefaultsToMediumAndMapsLegacyOff() {
    let suite = "aihud.tests.reasoning-effort.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(ReasoningEffort.load(from: defaults) == .medium)
    #expect(ReasoningEffort.default == .medium)
    defaults.set("off", forKey: ReasoningEffort.defaultsKey)
    #expect(ReasoningEffort.load(from: defaults) == .none)
    ReasoningEffort.save(.high, to: defaults)
    #expect(ReasoningEffort.load(from: defaults) == .high)
    #expect(ReasoningEffort.none.title == "None")
    #expect(ReasoningEffort.none.openAIValue == "none")
    #expect(ReasoningEffort.medium.openAIValue == "medium")
    #expect(ReasoningEffort.low.openAIValue == "low")
    #expect(ReasoningEffort.high.openAIValue == "high")
    #expect(ReasoningEffort.minimal.openAIValue == "minimal")
    #expect(ReasoningEffort.none.anthropicBudgetTokens == nil)
    #expect(ReasoningEffort.medium.anthropicBudgetTokens == 8_192)
    #expect(ReasoningEffort.minimal.anthropicBudgetTokens == 1_024)
}

@Test func anthropicLeavesThinkingOffWhenToolsAreSent() throws {
    // The reply that calls a tool must be echoed back with its signed thinking block, which the
    // assembler does not keep. Without thinking, the step after a tool call is accepted.
    let request = ChatRequest(
        url: URL(string: "https://api.anthropic.com/v1")!,
        model: "m",
        apiKey: "",
        messages: [OutboundMessage(role: "user", text: "find the invoice", imageJPEGs: [])],
        reasoningEffort: .medium,
        tools: AgentTools.definitions
    )
    let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnthropicBody(request: request))) as? [String: Any]
    #expect(body?["thinking"] == nil)
    #expect(body?["tools"] != nil)
}
