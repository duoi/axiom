import AppKit
import Foundation
import Testing
@testable import AIHUD

@Test func parserSkipsCommentsBlanksAndNonData() {
    #expect(SSEParser.parse(line: ": keep-alive") == .skip)
    #expect(SSEParser.parse(line: "") == .skip)
    #expect(SSEParser.parse(line: "event: ping") == .skip)
}

@Test func parserReadsContentAndIgnoresEmptyDeltas() {
    let token = SSEParser.parse(line: "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}")
    #expect(token == .token("Hi"))
    let role = SSEParser.parse(line: "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}")
    #expect(role == .skip)
    let nullContent = SSEParser.parse(line: "data: {\"choices\":[{\"delta\":{\"content\":null}}]}")
    #expect(nullContent == .skip)
    let reasoning = SSEParser.parse(line: "data: {\"choices\":[{\"delta\":{\"reasoning\":\"think\"}}]}")
    #expect(reasoning == .skip)
}

@Test func parserHandlesDoneAndErrors() {
    #expect(SSEParser.parse(line: "data: [DONE]") == .done)
    #expect(SSEParser.parse(line: "data:[DONE]\r") == .done)
    let failed = SSEParser.parse(line: "data: {\"error\":{\"message\":\"nope\"}}")
    #expect(failed == .failure("nope"))
}

@Test func completionsURLJoinsBaseAndKeepsFullPath() {
    let joined = EndpointResolver.completionsURL(configured: "https://api.openai.com/v1")
    #expect(joined == .success(URL(string: "https://api.openai.com/v1/chat/completions")!))
    let full = EndpointResolver.completionsURL(
        configured: "http://100.93.227.31:8080/v1/chat/completions",
        allowedCleartextHosts: ["100.93.227.31"]
    )
    #expect(full == .success(URL(string: "http://100.93.227.31:8080/v1/chat/completions")!))
    let slashed = EndpointResolver.completionsURL(configured: "https://api.openai.com/v1/")
    #expect(slashed == .success(URL(string: "https://api.openai.com/v1/chat/completions")!))
}

@Test func cleartextPolicyAllowsLoopbackAndDevHostOnly() {
    #expect(EndpointResolver.completionsURL(configured: "http://127.0.0.1:8080/v1").isSuccess)
    #expect(EndpointResolver.completionsURL(configured: "http://evil.example/v1") == .failure(.insecureHost))
    #expect(EndpointResolver.completionsURL(configured: "file:///tmp/x") == .failure(.fileURL))
    #expect(EndpointResolver.completionsURL(configured: "   ") == .failure(.empty))
    #expect(EndpointResolver.completionsURL(configured: "ftp://example.com/v1") == .failure(.unsupportedScheme))
}

@Test func redirectStaysOnTheSameHost() {
    let next = URL(string: "https://api.openai.com/v1/chat/completions")!
    #expect(RedirectPolicy.allows(originalHost: "api.openai.com", next: next))
    let other = URL(string: "https://evil.example/v1/chat/completions")!
    #expect(!RedirectPolicy.allows(originalHost: "api.openai.com", next: other))
}

@Test func sendBuildsAFollowUpAndStopKeepsThePartial() {
    var session = Session()
    session.draft = "  Hello  "
    guard case .request(let first) = session.send() else {
        Issue.record("expected a request")
        return
    }
    #expect(session.draft.isEmpty)
    #expect(session.phase == .waiting)
    #expect(first[0].role == "system")
    #expect(first[0].text == Preset.agent.systemPrompt)
    #expect(first[1].text == "Hello")

    session.receiveToken("Yo")
    session.stop()
    #expect(session.phase == .finished)
    #expect(session.displayAnswer == "Yo")
    #expect(session.showsStop == false)

    session.draft = "shorter"
    session.preset = .ask
    guard case .request(let second) = session.send() else {
        Issue.record("expected a follow-up")
        return
    }
    #expect(second.map(\.role) == ["system", "user", "assistant", "user"])
    #expect(second[0].text == Preset.ask.systemPrompt)
    #expect(second[2].text == "Yo")
    #expect(second[3].text == "shorter")
}

@Test func dismissDuringStreamRestoresTheDraft() {
    var session = Session()
    session.draft = "Keep me"
    _ = session.send()
    session.receiveToken("partial")
    let hid = session.dismiss(clickOutside: true)
    #expect(hid)
    #expect(session.draft == "Keep me")
    #expect(session.turns.isEmpty)
    #expect(session.displayAnswer.isEmpty)
    #expect(session.phase == .composing)
}

@Test func clickOutsideAfterAReplyDoesNotDismiss() {
    var session = Session()
    session.draft = "Hi"
    _ = session.send()
    session.receiveToken("Ok")
    session.finish()
    session.draft = "next"
    let stayed = session.dismiss(clickOutside: true)
    #expect(stayed == false)
    #expect(session.phase == .finished)
    #expect(session.draft == "next")
    let hid = session.dismiss(clickOutside: false)
    #expect(hid)
    #expect(session.turns.isEmpty)
    #expect(session.draft == "next")
}

@Test func failureRestoresTheDraftAndWhitespaceDoesNotSend() {
    var session = Session()
    session.draft = "   "
    let ignored = session.send()
    #expect(ignored == .ignored)
    session.draft = "Question"
    _ = session.send()
    session.fail("The request timed out.")
    #expect(session.draft == "Question")
    #expect(session.phase == .failed("The request timed out."))
    #expect(session.turns.isEmpty)
    #expect(session.showsStop == false)
}

@Test func attachmentLimitsRejectBinaryOversizeAndTooMany() {
    let text = AttachmentPolicy.prepare(data: Data("hello".utf8), filename: "note.txt", existingCount: 0)
    guard case .success(let chip) = text, case .text("hello") = chip.payload else {
        Issue.record("expected text")
        return
    }
    #expect(chip.name == "note.txt")
    #expect(AttachmentPolicy.prepare(data: Data([0, 1, 2]), filename: "bad.txt", existingCount: 0) == .failure(.binary))
    let huge = Data(count: AttachmentPolicy.maxBytes + 1)
    #expect(AttachmentPolicy.prepare(data: huge, filename: "big.txt", existingCount: 0) == .failure(.tooLarge))
    #expect(AttachmentPolicy.prepare(data: Data("x".utf8), filename: "note.txt", existingCount: 4) == .failure(.tooMany))
    #expect(AttachmentPolicy.prepare(data: Data("x".utf8), filename: "bin.exe", existingCount: 0) == .failure(.unsupported))
}

@Test func imageAttachmentBecomesJPEG() {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    let png = rep?.representation(using: .png, properties: [:]) ?? Data()
    let result = AttachmentPolicy.prepare(data: png, filename: "dot.png", existingCount: 0)
    guard case .success(let chip) = result, case .jpeg(let jpeg) = chip.payload else {
        Issue.record("expected jpeg")
        return
    }
    #expect(jpeg.starts(with: [0xFF, 0xD8]))
}

private extension Result where Failure == EndpointError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
