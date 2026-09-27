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

@Test func expandedHistoryListsEachTurnOnce() {
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi")
    session.finish()
    session.draft = "How are you"
    _ = session.send()
    session.receiveToken("Fine")

    let streaming = Transcript.rows(in: session, expanded: true)
    #expect(streaming.map(\.text) == ["Hello", "Hi", "How are you", "Fine"])
    #expect(streaming.filter(\.live).map(\.text) == ["Fine"])

    session.finish()
    let done = Transcript.rows(in: session, expanded: true)
    #expect(done.map(\.text) == ["Hello", "Hi", "How are you", "Fine"])
    #expect(done.allSatisfy { !$0.live })
    #expect(session.startedAt != nil)
    #expect(done.allSatisfy { $0.chipNames.isEmpty || $0.kind == .user })
}

@Test func markupSplitsBoldLists() {
    let runs = LightMarkup.parse("Hello **there**\n1. First\n- Item")
    #expect(runs == [.plain("Hello "), .bold("there"), .numbered(1, "First"), .bullet("Item")])
}

@Test func pillInsetIsTheSameOnEverySide() {
    let inset = HUDMetrics.pillInset
    #expect(inset > 0)
    #expect(HUDMetrics.pillInsets == HUDInsets.equal(inset))
    #expect(HUDMetrics.pillInsets.top == HUDMetrics.pillInsets.leading)
    #expect(HUDMetrics.pillInsets.bottom == HUDMetrics.pillInsets.trailing)
}

@Test func glassIsClearAndMatteIsRegular() {
    #expect(HUDMaterial.effectStyle(matte: false) == .clear)
    #expect(HUDMaterial.effectStyle(matte: true) == .regular)
    #expect(!HUDMaterial.usesSolidCard(reduceTransparency: false))
    #expect(HUDMaterial.usesSolidCard(reduceTransparency: true))
}

@Test func selectedPillIsMatteWhenTheCardIsNotKey() {
    #expect(!HUDMaterial.pillIsMatte(preference: false, reduceTransparency: false, cardIsKey: true))
    #expect(HUDMaterial.pillIsMatte(preference: false, reduceTransparency: false, cardIsKey: false))
    #expect(HUDMaterial.pillIsMatte(preference: true, reduceTransparency: false, cardIsKey: true))
    #expect(HUDMaterial.pillIsMatte(preference: false, reduceTransparency: true, cardIsKey: true))
    #expect(HUDMaterial.effectStyle(matte: HUDMaterial.pillIsMatte(preference: false, reduceTransparency: false, cardIsKey: false)) == .regular)
}

@Test func glassVeilClearsAtFullAmountAndTintsAsThePercentDrops() {
    #expect(HUDMaterial.veilOpacity(glassAmount: 1) == 0)
    #expect(HUDMaterial.veilOpacity(glassAmount: 0.99) == 0)
    #expect(HUDMaterial.veilOpacity(glassAmount: 0.5) == 0.5)
    #expect(HUDMaterial.veilOpacity(glassAmount: 0) == 1)
    #expect(HUDMaterial.clampAmount(1.4) == 1)
    #expect(HUDMaterial.clampAmount(-0.2) == 0)
}

@Test func glassAmountPersistsAsAPercent() {
    let defaults = UserDefaults(suiteName: "aihud.tests.glass-amount")!
    defaults.removePersistentDomain(forName: "aihud.tests.glass-amount")
    #expect(HUDMaterial.loadAmount(from: defaults) == 1)
    HUDMaterial.saveAmount(0.4, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 0.4)
    HUDMaterial.saveAmount(2, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 1)
    defaults.removePersistentDomain(forName: "aihud.tests.glass-amount")
}

@Test func onDeviceOffUsesTheCloudTarget() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test"
    )
    let route = ChatRouting.decide(onDevice: false, availability: .available, cloud: ready)
    #expect(route == .cloud(ready))
    let blocked = SendTarget.blocked("Add an API key in Settings")
    let unavailable = ChatRouting.decide(onDevice: false, availability: .notEnabled, cloud: blocked)
    #expect(unavailable == .cloud(blocked))
}

@Test func onDeviceOnUsesTheOnDevicePathWhenAvailable() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test"
    )
    let route = ChatRouting.decide(onDevice: true, availability: .available, cloud: ready)
    #expect(route == .onDevice)
}

@Test func onDeviceOnBlocksInsteadOfFallingBack() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test"
    )
    let off = ChatRouting.decide(onDevice: true, availability: .notEnabled, cloud: ready)
    #expect(off == .blocked("Apple Intelligence is off."))
    let ineligible = ChatRouting.decide(onDevice: true, availability: .notEligible, cloud: ready)
    #expect(ineligible == .blocked("This Mac is not eligible for Apple Intelligence."))
    let downloading = ChatRouting.decide(onDevice: true, availability: .notReady, cloud: ready)
    #expect(downloading == .blocked("The on-device model is still downloading."))
    let other = ChatRouting.decide(onDevice: true, availability: .other, cloud: ready)
    #expect(other == .blocked("The on-device model is not available."))
}

@Test func onDeviceOnSendsImagesToVisionOrAttachment() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test"
    )
    let vision = ChatRouting.decide(
        onDevice: true,
        availability: .available,
        cloud: ready,
        hasImage: true,
        visionConfigured: true,
        supportsOnDeviceImage: false
    )
    #expect(vision == .cloud(ready))
    let attach = ChatRouting.decide(
        onDevice: true,
        availability: .available,
        cloud: ready,
        hasImage: true,
        visionConfigured: false,
        supportsOnDeviceImage: true
    )
    #expect(attach == .onDevice)
    let blocked = ChatRouting.decide(
        onDevice: true,
        availability: .available,
        cloud: ready,
        hasImage: true,
        visionConfigured: false,
        supportsOnDeviceImage: false
    )
    #expect(blocked == .blocked("The on-device model cannot take that image."))
}

@Test func togglingOnDeviceDoesNotClearStoredEndpointFields() {
    let suite = "aihud.tests.on-device-persist"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    ChatSettings.saveOnDevice(true, to: defaults)
    #expect(defaults.bool(forKey: ChatSettings.onDeviceKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    ChatSettings.saveOnDevice(false, to: defaults)
    #expect(!defaults.bool(forKey: ChatSettings.onDeviceKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}

@Test func visionEndpointIsUsedOnlyWhenAnImageIsPresent() {
    let chat = ServiceCredentials(url: "https://api.openai.com/v1", model: "gpt-4o", apiKey: "chat")
    let vision = ServiceCredentials(
        url: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini",
        apiKey: "gem"
    )
    let blank = ServiceCredentials(url: "", model: "", apiKey: "")
    let incomplete = ServiceCredentials(url: "https://generativelanguage.googleapis.com/v1beta", model: "", apiKey: "")
    #expect(ModelChoice.pick(chat: chat, vision: blank, hasImage: true) == chat)
    #expect(ModelChoice.pick(chat: chat, vision: vision, hasImage: false) == chat)
    #expect(ModelChoice.pick(chat: chat, vision: vision, hasImage: true) == vision)
    #expect(ModelChoice.visionIsIncomplete(incomplete))
    #expect(!ModelChoice.visionIsIncomplete(blank))
    #expect(!ModelChoice.visionIsIncomplete(vision))
}

@Test func screenJPEGUsesTheSmallerPassWhenTheFirstIsOverBudget() {
    var calls: [(Int, CGFloat)] = []
    let data = ScreenImage.choose { edge, quality in
        calls.append((edge, quality))
        if edge == 1536 {
            return Data(count: 500_000)
        }
        return Data(count: 1_000)
    }
    #expect(calls.count == 2)
    #expect(calls[0].0 == 1536)
    #expect(calls[0].1 == 0.60)
    #expect(calls[1].0 == 1280)
    #expect(calls[1].1 == 0.50)
    #expect(data.count == 1_000)
}

@Test func screenJPEGStaysWithinTheLongEdgeAndBudget() {
    let width = 2200
    let height = 900
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for x in stride(from: 0, to: width, by: 3) {
        for y in stride(from: 0, to: height, by: 3) {
            context.setFillColor(CGColor(
                red: CGFloat(x % 255) / 255,
                green: CGFloat(y % 255) / 255,
                blue: CGFloat((x + y) % 255) / 255,
                alpha: 1
            ))
            context.fill(CGRect(x: x, y: y, width: 3, height: 3))
        }
    }
    let image = context.makeImage()!
    let jpeg = ScreenImage.jpeg(from: image)
    #expect(jpeg.starts(with: [0xFF, 0xD8]))
    #expect(jpeg.count <= ScreenImage.budget)
    let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(max(decoded.width, decoded.height) <= 1536)
}

private extension Result where Failure == EndpointError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
