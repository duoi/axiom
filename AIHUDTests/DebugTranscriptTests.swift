import Foundation
import Testing
@testable import Axiom

@Test func debugTranscriptRedactsBearerAndAPIKeyHeaders() {
    var request = URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer sk-live-SECRET-token-999", forHTTPHeaderField: "Authorization")
    request.setValue("anthropic-secret-key-xyz", forHTTPHeaderField: "x-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = #"""
    {"model":"gpt-4.1","stream":true,"messages":[{"role":"user","content":"What is the mass of the sun?"}],"api_key":"json-secret-should-go","refresh_token":"refresh-secret-abc"}
    """#.data(using: .utf8)

    let dump = DebugHTTPTranscript.formatRequest(request)

    #expect(dump.contains("POST"))
    #expect(dump.contains("api.example.com"))
    #expect(dump.contains("/v1/chat/completions"))
    #expect(dump.contains("What is the mass of the sun?"))
    #expect(dump.contains("gpt-4.1"))
    #expect(dump.contains("[redacted]"))
    #expect(!dump.contains("sk-live-SECRET-token-999"))
    #expect(!dump.contains("anthropic-secret-key-xyz"))
    #expect(!dump.contains("json-secret-should-go"))
    #expect(!dump.contains("refresh-secret-abc"))
    #expect(dump.contains("Authorization: [redacted]") || dump.lowercased().contains("authorization: [redacted]"))
    #expect(dump.lowercased().contains("x-api-key: [redacted]"))
}

@Test func debugTranscriptKeepsPromptAndRedactsQuerySecrets() {
    let url = URL(string: "https://host.example/v1/messages?api_key=query-secret&foo=bar")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("api-key-header-secret", forHTTPHeaderField: "api-key")
    request.httpBody = #"{"model":"claude","messages":[{"role":"user","content":"Keep this prompt"}]}"#
        .data(using: .utf8)

    let dump = DebugHTTPTranscript.formatRequest(request)
    #expect(dump.contains("Keep this prompt"))
    #expect(dump.contains("host.example"))
    #expect(dump.contains("/v1/messages"))
    #expect(!dump.contains("query-secret"))
    #expect(!dump.contains("api-key-header-secret"))
    #expect(dump.contains("[redacted]"))
}

@Test @MainActor
func debugTranscriptAppendsSSELinesWithoutWaitingForDone() {
    DebugHTTPTranscript.setArmed(true)
    defer { DebugHTTPTranscript.setArmed(false) }
    let store = DebugTranscriptStore.makeIsolatedForTests()
    DebugHTTPTranscript.bindStoreForTests(store)
    defer { DebugHTTPTranscript.bindStoreForTests(nil) }

    DebugHTTPTranscript.recordLine("data: {\"delta\":\"Hel\"}")
    DebugHTTPTranscript.recordLine("data: {\"delta\":\"lo\"}")
    DebugHTTPTranscript.recordFinished()

    #expect(store.text.contains("data: {\"delta\":\"Hel\"}"))
    #expect(store.text.contains("data: {\"delta\":\"lo\"}"))
    #expect(store.text.contains("-- stream end --"))
}

@Test func unknownTranscriptDebugCommandDoesNotCrash() {
    #expect(DebugRouting.parse("open-transcript-panel-please") == nil)
    #expect(DebugRouting.phase(for: "open-transcript-panel-please") == nil)
    let session = DebugRouting.apply("open-transcript-panel-please", to: Session())
    #expect(session.phase == .composing)
}
