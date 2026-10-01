import Foundation
import Testing
@testable import Axiom

@Test func askIsTheDefaultAndExperimentalChoosesAgentAndTools() {
    #expect(Session().preset == .ask)
    #expect(AgentModePolicy.preset(experimental: false, prefersAgent: true) == .ask)
    #expect(AgentModePolicy.preset(experimental: true, prefersAgent: false) == .ask)
    #expect(AgentModePolicy.preset(experimental: true, prefersAgent: true) == .agent)
    #expect(!AgentModePolicy.toolsEnabled(experimental: false, preset: .agent, prefersAgent: true))
    #expect(!AgentModePolicy.toolsEnabled(experimental: true, preset: .ask, prefersAgent: true))
    #expect(!AgentModePolicy.toolsEnabled(experimental: true, preset: .agent, prefersAgent: false))
    #expect(AgentModePolicy.toolsEnabled(experimental: true, preset: .agent, prefersAgent: true))
    #expect(!AgentModePolicy.showsPresetControl(experimental: false, prefersAgent: true))
    #expect(!AgentModePolicy.showsPresetControl(experimental: true, prefersAgent: false))
    #expect(AgentModePolicy.showsPresetControl(experimental: true, prefersAgent: true))

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let ask = SystemPrompt.composed(override: "", preset: .ask, now: now, toolsEnabled: true)
    #expect(ask.contains(Preset.ask.systemPrompt))
    #expect(ask.contains("80 words"))
    #expect(!ask.contains("fetch_url"))
    let agent = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: false)
    #expect(agent.contains("You cannot run tools"))
    #expect(agent.contains("80 words"))
    let tools = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: true)
    #expect(tools.contains("fetch_url"))
    #expect(tools.contains("glob"))
    #expect(!tools.contains("You cannot run tools"))
    #expect(!tools.contains("80 words"))
}

@Test func endpointModeFlagsDefaultOffWhenMissing() throws {
    let json = """
    {"id":"00000000-0000-4000-A1D0-000000000001","name":"Local","completionsURL":"http://127.0.0.1:11434/v1","model":"m","systemPrompt":""}
    """.data(using: .utf8)!
    let endpoint = try JSONDecoder().decode(ChatEndpoint.self, from: json)
    #expect(!endpoint.enablesTools)
    #expect(!endpoint.prefersAgent)
    let toolsOnly = """
    {"id":"00000000-0000-4000-A1D0-000000000002","name":"Local","completionsURL":"http://127.0.0.1:11434/v1","model":"m","systemPrompt":"","enablesTools":true}
    """.data(using: .utf8)!
    let migrated = try JSONDecoder().decode(ChatEndpoint.self, from: toolsOnly)
    #expect(migrated.prefersAgent)
    #expect(migrated.enablesTools)
}

@Test func experimentalAgentDefaultsOff() {
    let name = "axiom-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    #expect(ExperimentalAgent.load(from: defaults) == false)
    ExperimentalAgent.save(true, to: defaults)
    #expect(ExperimentalAgent.load(from: defaults) == true)
    defaults.removePersistentDomain(forName: name)
}

@Test func agentPromptStaysPlanOnlyUntilExperimentalToolsAreOn() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let off = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: false)
    #expect(off.contains("You cannot run tools"))
    #expect(off.contains("80 words"))
    let on = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: true)
    #expect(!on.contains("You cannot run tools"))
    #expect(!on.contains("80 words"))
    #expect(on.contains("fetch_url"))
    #expect(on.contains("open_url"))
    let custom = SystemPrompt.composed(override: "Only JSON.", preset: .agent, now: now, toolsEnabled: true)
    #expect(custom.contains("Only JSON."))
    #expect(custom.contains("fetch_url"))
    #expect(!custom.contains("You cannot run tools"))
}

@Test func askPromptIgnoresExperimentalTools() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let on = SystemPrompt.composed(override: "", preset: .ask, now: now, toolsEnabled: true)
    #expect(on.contains(Preset.ask.systemPrompt))
    #expect(on.contains("80 words"))
    #expect(!on.contains("fetch_url"))
}

@Test func completionsAssemblerBuildsToolCallsByIndex() {
    let lines = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"fetch_url","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"url\":"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"https://example.com\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"content":"Looking."}}]}"#,
        #"data: {"choices":[{"finish_reason":"tool_calls"}]}"#,
        "data: [DONE]",
    ]
    let assembled = ToolCallAssembler.completions(lines: lines)
    #expect(assembled.text == "Looking.")
    #expect(assembled.truncated == false)
    #expect(assembled.calls == [
        ToolCall(id: "call_1", name: "fetch_url", arguments: #"{"url":"https://example.com"}"#)
    ])
}

@Test func completionsAssemblerMarksLengthCutoffUnusable() {
    let lines = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_9","function":{"name":"fetch_url","arguments":"{\"url\":"}}]}}]}"#,
        #"data: {"choices":[{"finish_reason":"length"}]}"#,
        "data: [DONE]",
    ]
    let assembled = ToolCallAssembler.completions(lines: lines)
    #expect(assembled.truncated)
    #expect(assembled.calls.count == 1)
    #expect(assembled.calls[0].id == "call_9")
}

@Test func anthropicAssemblerReadsToolUseBlocks() {
    let lines = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"open_url","input":{}}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"url\":"}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"https://example.com\"}"}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Ok"}}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
        #"data: {"type":"message_stop"}"#,
    ]
    let assembled = ToolCallAssembler.anthropic(lines: lines)
    #expect(assembled.text == "Ok")
    #expect(assembled.truncated == false)
    #expect(assembled.calls == [
        ToolCall(id: "toolu_1", name: "open_url", arguments: #"{"url":"https://example.com"}"#)
    ])
}

@Test func anthropicAssemblerMarksMaxTokensUnusable() {
    let lines = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_2","name":"fetch_url","input":{}}}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
        #"data: {"type":"message_stop"}"#,
    ]
    let assembled = ToolCallAssembler.anthropic(lines: lines)
    #expect(assembled.truncated)
    #expect(assembled.calls[0].id == "toolu_2")
}

@Test func responsesAssemblerReadsFunctionCalls() {
    let lines = [
        #"data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","call_id":"call_3","name":"fetch_url","arguments":""}}"#,
        #"data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\"url\":\"https://example.com\"}"}"#,
        #"data: {"type":"response.output_text.delta","delta":"Hi"}"#,
        #"data: {"type":"response.completed"}"#,
    ]
    let assembled = ToolCallAssembler.responses(lines: lines)
    #expect(assembled.text == "Hi")
    #expect(assembled.truncated == false)
    #expect(assembled.calls == [
        ToolCall(id: "call_3", name: "fetch_url", arguments: #"{"url":"https://example.com"}"#)
    ])
}

@Test func responsesAssemblerMarksIncompleteUnusable() {
    let lines = [
        #"data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","call_id":"call_4","name":"fetch_url","arguments":""}}"#,
        #"data: {"type":"response.incomplete"}"#,
    ]
    let assembled = ToolCallAssembler.responses(lines: lines)
    #expect(assembled.truncated)
    #expect(assembled.calls[0].id == "call_4")
}

@Test func agentLoopStopsWhenTheModelDoesNotCallATool() {
    let outcome = AgentLoop.run(
        sample: { _ in
            AgentLoop.Turn(text: "Just text.", calls: [], truncated: false)
        },
        execute: { _ in
            Issue.record("no tool should run")
            return ToolResult(toolCallID: "", name: "", text: "", isError: true)
        }
    )
    #expect(outcome.modelCalls == 1)
    #expect(outcome.results.isEmpty)
    #expect(outcome.text == "Just text.")
    #expect(outcome.stoppedForCap == false)
}

@Test func agentLoopContinuesAfterAToolResult() {
    let outcome = AgentLoop.run(
        sample: { results in
            if results.isEmpty {
                return AgentLoop.Turn(
                    text: "",
                    calls: [ToolCall(id: "c1", name: "fetch_url", arguments: #"{"url":"https://example.com"}"#)],
                    truncated: false
                )
            }
            return AgentLoop.Turn(text: "Done.", calls: [], truncated: false)
        },
        execute: { call in
            ToolResult(toolCallID: call.id, name: call.name, text: "page", isError: false)
        }
    )
    #expect(outcome.modelCalls == 2)
    #expect(outcome.results.count == 1)
    #expect(outcome.results[0].text == "page")
    #expect(outcome.text == "Done.")
}

@Test func agentLoopStopsAtTheStepCap() {
    let outcome = AgentLoop.run(
        sample: { _ in
            AgentLoop.Turn(
                text: "again",
                calls: [ToolCall(id: "c", name: "fetch_url", arguments: "{}")],
                truncated: false
            )
        },
        execute: { call in
            ToolResult(toolCallID: call.id, name: call.name, text: "ok", isError: false)
        }
    )
    #expect(AgentLoop.stepCap == 8)
    #expect(outcome.modelCalls == 8)
    #expect(outcome.results.count == 8)
    #expect(outcome.stoppedForCap)
}

@Test func agentLoopDoesNotExecuteTruncatedCalls() {
    var ran = 0
    let outcome = AgentLoop.run(
        sample: { results in
            if results.isEmpty {
                return AgentLoop.Turn(
                    text: "",
                    calls: [ToolCall(id: "cut", name: "fetch_url", arguments: "{\"url\":")],
                    truncated: true
                )
            }
            return AgentLoop.Turn(text: "retry", calls: [], truncated: false)
        },
        execute: { _ in
            ran += 1
            return ToolResult(toolCallID: "", name: "", text: "", isError: false)
        }
    )
    #expect(ran == 0)
    #expect(outcome.results.count == 1)
    #expect(outcome.results[0].isError)
    #expect(outcome.results[0].toolCallID == "cut")
    #expect(outcome.modelCalls == 2)
    #expect(outcome.text == "retry")
}

@Test func unknownToolIsAnErrorResultTheLoopKeeps() {
    let call = ToolCall(id: "u", name: "nope", arguments: "{}")
    let outcome = AgentLoop.run(
        sample: { results in
            if results.isEmpty {
                return AgentLoop.Turn(text: "", calls: [call], truncated: false)
            }
            return AgentLoop.Turn(text: "noted", calls: [], truncated: false)
        },
        execute: { AgentTools.unknownResult($0) }
    )
    #expect(outcome.results[0].isError)
    #expect(outcome.results[0].text.contains("nope"))
    #expect(outcome.text == "noted")
}

@Test func fetchAllowsHTTPSAndKnownCleartextOnly() {
    #expect(FetchURLPolicy.allows(URL(string: "https://example.com/a")!))
    #expect(FetchURLPolicy.allows(URL(string: "http://127.0.0.1:8080/x")!))
    #expect(FetchURLPolicy.allows(
        URL(string: "http://dev.example/x")!,
        allowedCleartextHosts: ["dev.example"]
    ))
    #expect(!FetchURLPolicy.allows(URL(string: "http://evil.example/x")!))
    #expect(!FetchURLPolicy.allows(URL(string: "file:///etc/passwd")!))
    #expect(FetchURLPolicy.url(from: #"{"url":"https://example.com"}"#) == URL(string: "https://example.com"))
    #expect(FetchURLPolicy.url(from: "not-json") == nil)
}

@Test func fetchElidesLongTextAndStripsHTML() {
    let short = String(repeating: "a", count: 10_000)
    #expect(FetchURLPolicy.elide(short) == short)
    let long = String(repeating: "b", count: 10_001)
    let elided = FetchURLPolicy.elide(long)
    #expect(elided.contains("Output too long."))
    #expect(elided.hasPrefix(String(repeating: "b", count: 5_000)))
    #expect(elided.hasSuffix(String(repeating: "b", count: 5_000)))
    let page = "<html><body><p>Hello</p><script>secret()</script></body></html>"
    let text = FetchURLPolicy.readableText(page, contentType: "text/html")
    #expect(text.contains("Hello"))
    #expect(!text.contains("<p>"))
    #expect(!text.contains("secret"))
}

@Test func openURLAsksAndFetchDoesNot() {
    #expect(AgentTools.needsApproval("open_url"))
    #expect(!AgentTools.needsApproval("fetch_url"))
}

@Test func toolBodiesStayOffUntilTheRegistryIsSent() throws {
    let request = ChatRequest(
        url: URL(string: "https://example.com/v1/chat/completions")!,
        model: "m",
        apiKey: "",
        messages: [OutboundMessage(role: "user", text: "hi", imageJPEGs: [])]
    )
    let completions = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatBody(request: request))) as? [String: Any]
    )
    #expect(completions["tools"] == nil)
    let anthropic = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(AnthropicBody(request: request))) as? [String: Any]
    )
    #expect(anthropic["tools"] == nil)
    let responses = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ResponsesBody(request: request))) as? [String: Any]
    )
    #expect(responses["tools"] == nil)
}

@Test func toolBodiesIncludeTheRegistryAndResults() throws {
    let call = ToolCall(id: "call_1", name: "fetch_url", arguments: #"{"url":"https://example.com"}"#)
    let request = ChatRequest(
        url: URL(string: "https://example.com/v1/chat/completions")!,
        model: "m",
        apiKey: "",
        messages: [
            OutboundMessage(role: "user", text: "look", imageJPEGs: []),
            OutboundMessage(role: "assistant", text: "", imageJPEGs: [], toolCalls: [call]),
            OutboundMessage(role: "tool", text: "page", imageJPEGs: [], toolCallID: "call_1"),
        ],
        tools: AgentTools.definitions
    )

    let completions = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatBody(request: request))) as? [String: Any]
    )
    let tools = try #require(completions["tools"] as? [[String: Any]])
    #expect(tools.count == 5)
    let function = try #require(tools[0]["function"] as? [String: Any])
    #expect(function["name"] as? String == "fetch_url")
    let messages = try #require(completions["messages"] as? [[String: Any]])
    let toolCalls = try #require(messages[1]["tool_calls"] as? [[String: Any]])
    #expect(toolCalls[0]["id"] as? String == "call_1")
    #expect(messages[2]["role"] as? String == "tool")
    #expect(messages[2]["tool_call_id"] as? String == "call_1")
    #expect(messages[2]["content"] as? String == "page")

    let anthropic = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(AnthropicBody(request: request))) as? [String: Any]
    )
    let anthropicTools = try #require(anthropic["tools"] as? [[String: Any]])
    #expect(anthropicTools[0]["name"] as? String == "fetch_url")
    #expect(anthropicTools[0]["input_schema"] != nil)
    let anthropicMessages = try #require(anthropic["messages"] as? [[String: Any]])
    let assistant = try #require(anthropicMessages[1]["content"] as? [[String: Any]])
    #expect(assistant.contains { $0["type"] as? String == "tool_use" })
    let toolUser = try #require(anthropicMessages[2]["content"] as? [[String: Any]])
    #expect(toolUser[0]["type"] as? String == "tool_result")
    #expect(toolUser[0]["tool_use_id"] as? String == "call_1")
    #expect(toolUser[0]["is_error"] == nil)

    let failed = ChatRequest(
        url: URL(string: "https://example.com/v1/messages")!,
        model: "m",
        apiKey: "",
        messages: [
            OutboundMessage(
                role: "tool",
                text: "The fetch failed.",
                imageJPEGs: [],
                toolCallID: "call_1",
                toolIsError: true
            ),
        ]
    )
    let failedBody = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(AnthropicBody(request: failed))) as? [String: Any]
    )
    let failedMessages = try #require(failedBody["messages"] as? [[String: Any]])
    let failedParts = try #require(failedMessages[0]["content"] as? [[String: Any]])
    #expect(failedParts[0]["is_error"] as? Bool == true)

    let responses = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ResponsesBody(request: request))) as? [String: Any]
    )
    let responseTools = try #require(responses["tools"] as? [[String: Any]])
    #expect(responseTools[0]["name"] as? String == "fetch_url")
    let input = try #require(responses["input"] as? [[String: Any]])
    #expect(input.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "call_1" })
    #expect(input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == "call_1" })
}

@Test func toolLineOpensTheReplyRegion() {
    #expect(
        HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .streaming,
            historyExpanded: false,
            toolLine: "Fetching example.com"
        )
    )
    #expect(
        !HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .waiting,
            historyExpanded: false,
            toolLine: nil
        )
    )
}

@Test func folderToolsJoinTheExperimentalRegistry() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let on = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: true)
    #expect(on.contains("glob"))
    #expect(on.contains("grep"))
    #expect(on.contains("read"))
    let off = SystemPrompt.composed(override: "", preset: .agent, now: now, toolsEnabled: false)
    #expect(!off.contains("glob"))
    let names = AgentTools.definitions.map(\.name)
    #expect(names == ["fetch_url", "open_url", "glob", "grep", "read"])
    let request = ChatRequest(
        url: URL(string: "https://example.com/v1/chat/completions")!,
        model: "m",
        apiKey: "",
        messages: [OutboundMessage(role: "user", text: "hi", imageJPEGs: [])],
        tools: AgentTools.definitions
    )
    let body = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatBody(request: request))) as? [String: Any]
    )
    let tools = try #require(body["tools"] as? [[String: Any]])
    let grep = try #require(tools.first { (($0["function"] as? [String: Any])?["name"] as? String) == "grep" })
    let function = try #require(grep["function"] as? [String: Any])
    let parameters = try #require(function["parameters"] as? [String: Any])
    let required = try #require(parameters["required"] as? [String])
    #expect(required == ["query"])
    #expect(!AgentTools.needsApproval("glob"))
    #expect(!AgentTools.needsApproval("grep"))
    #expect(!AgentTools.needsApproval("read"))
}

@Test func folderSearchFindsByNameAndByTextAndStaysInsideTheRoot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("axiom-folder-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/more", isDirectory: true), withIntermediateDirectories: true)
    let note = root.appendingPathComponent("docs/note.txt")
    try "hello invoice\nsecond line\n".write(to: note, atomically: true, encoding: .utf8)
    try "deep\n".write(to: root.appendingPathComponent("docs/more/note.txt"), atomically: true, encoding: .utf8)
    try Data([0x00, 0x01]).write(to: root.appendingPathComponent("docs/blob.bin"))
    let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("axiom-outside-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    let secret = outsideDir.appendingPathComponent("secret.txt")
    try "secret invoice\n".write(to: secret, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/linked.txt"), withDestinationURL: secret)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outsideDir)
    }

    let named = FolderSearch.run(root: root, name: "glob", arguments: ["pattern": "*.txt"])
    #expect(!named.isError)
    #expect(named.text.contains("docs/note.txt"))
    #expect(named.text.contains("docs/more/note.txt"))
    #expect(!named.text.contains("secret"))
    #expect(!named.text.contains("linked.txt"))

    let shallow = FolderSearch.run(root: root, name: "glob", arguments: ["pattern": "docs/*.txt"])
    #expect(shallow.text.contains("docs/note.txt"))
    #expect(!shallow.text.contains("docs/more/note.txt"))

    let found = FolderSearch.run(root: root, name: "grep", arguments: ["query": "invoice"])
    #expect(!found.isError)
    #expect(found.text.contains("docs/note.txt:1:hello invoice"))
    #expect(!found.text.contains("secret"))

    let page = FolderSearch.run(root: root, name: "read", arguments: ["path": "docs/note.txt", "offset": "2", "limit": "1"])
    #expect(!page.isError)
    #expect(page.text.contains("2|second line"))
    #expect(!page.text.contains("hello invoice"))

    let escaped = FolderSearch.run(root: root, name: "read", arguments: ["path": "../secret.txt"])
    #expect(escaped.isError)
    let linked = FolderSearch.run(root: root, name: "read", arguments: ["path": "docs/linked.txt"])
    #expect(linked.isError)
    let missing = FolderSearch.run(root: nil, name: "grep", arguments: ["query": "invoice"])
    #expect(missing.isError)
    #expect(missing.text.contains("No folder is selected"))
}

@Test func folderBookmarkRoundTripsTheChosenDirectory() throws {
    let name = "axiom-folder-grant-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(FolderGrant.url(from: defaults) == nil)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("axiom-grant-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = try #require(FolderGrant.data(for: root))
    defaults.set(data, forKey: FolderGrant.defaultsKey)
    let loaded = try #require(FolderGrant.url(from: defaults))
    #expect(loaded.lastPathComponent == root.lastPathComponent)
    FolderGrant.clear(in: defaults)
    #expect(FolderGrant.url(from: defaults) == nil)
}
