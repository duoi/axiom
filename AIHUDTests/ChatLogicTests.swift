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
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let prompt = SystemPrompt.composed(override: "", preset: .agent, now: now)
    guard case .request(let first) = session.send(systemPrompt: prompt) else {
        Issue.record("expected a request")
        return
    }
    #expect(session.draft.isEmpty)
    #expect(session.phase == .waiting)
    #expect(first[0].role == "system")
    #expect(first[0].text == prompt)
    #expect(first[1].text == "Hello")

    session.receiveToken("Yo")
    session.stop()
    #expect(session.phase == .finished)
    #expect(session.displayAnswer == "Yo")
    #expect(session.showsStop == false)

    session.draft = "shorter"
    session.preset = .ask
    let askPrompt = SystemPrompt.composed(override: "", preset: .ask, now: now)
    guard case .request(let second) = session.send(systemPrompt: askPrompt) else {
        Issue.record("expected a follow-up")
        return
    }
    #expect(second.map(\.role) == ["system", "user", "assistant", "user"])
    #expect(second[0].text == askPrompt)
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

@Test func catalogMigratesLegacySingleEndpoint() {
    let suite = "aihud.tests.endpoint-migrate"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    let loaded = ChatEndpointCatalog.load(from: defaults)
    #expect(loaded.didMigrate)
    #expect(loaded.endpoints.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    let openai = loaded.endpoints.first { $0.presetID == "openai" }
    #expect(openai?.name == ChatEndpointCatalog.migratedName)
    #expect(openai?.completionsURL == "https://api.openai.com/v1")
    #expect(openai?.model == "gpt-4o")
    #expect(openai?.systemPrompt.isEmpty == true)
    #expect(openai?.kind == .openaiCompatible)
    #expect(loaded.defaultID == openai?.id)
    #expect(loaded.endpoints.filter { $0.presetID == "openai" }.count == 1)
    defaults.removePersistentDomain(forName: suite)
}

@Test func catalogKeepsStoredEndpointsAndSelectedDefault() {
    let suite = "aihud.tests.endpoint-default"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let first = ChatEndpoint(
        id: UUID(),
        name: "Work",
        completionsURL: "https://work.example/v1",
        model: "opus",
        systemPrompt: "Be brief"
    )
    let second = ChatEndpoint(
        id: UUID(),
        name: "Home",
        completionsURL: "https://home.example/v1",
        model: "gpt-4o",
        systemPrompt: ""
    )
    ChatEndpointCatalog.save(endpoints: [first, second], defaultID: second.id, to: defaults)
    defaults.set("https://legacy.example/v1", forKey: ChatSettings.urlKey)
    defaults.set("legacy-model", forKey: ChatSettings.modelKey)
    let loaded = ChatEndpointCatalog.load(from: defaults)
    #expect(loaded.didMigrate)
    #expect(loaded.endpoints.contains(first))
    #expect(loaded.endpoints.contains(second))
    #expect(loaded.endpoints.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    #expect(loaded.defaultID == second.id)
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: loaded.endpoints, defaultID: loaded.defaultID) == second)
    defaults.removePersistentDomain(forName: suite)
}

@Test func missingDefaultFallsBackOrBlocksWithoutCrashing() {
    let first = ChatEndpoint(
        id: UUID(),
        name: "A",
        completionsURL: "https://a.example/v1",
        model: "a",
        systemPrompt: ""
    )
    let second = ChatEndpoint(
        id: UUID(),
        name: "B",
        completionsURL: "https://b.example/v1",
        model: "b",
        systemPrompt: ""
    )
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: [first, second], defaultID: second.id) == second)
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: [first, second], defaultID: UUID()) == first)
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: [first, second], defaultID: nil) == first)
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: [], defaultID: UUID()) == nil)
    let withOnDevice = ChatEndpointCatalog.ensuringOnDevice([first, second])
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: withOnDevice, defaultID: nil) == first)
    let blocked = ChatEndpointCatalog.target(
        endpoint: nil,
        apiKey: "",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    #expect(blocked == .blocked(ChatEndpointCatalog.missingEndpointMessage))
}

@Test func systemPromptReplacesDatetimeFromInjectedClock() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let locale = Locale(identifier: "en_US_POSIX")
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let formatted = SystemPrompt.formattedDateTime(now, locale: locale, timeZone: timeZone)
    #expect(!formatted.isEmpty)
    #expect(!formatted.contains(SystemPrompt.datetimeToken))

    let defaulted = SystemPrompt.resolve(override: "", now: now, locale: locale, timeZone: timeZone)
    #expect(defaulted.hasPrefix("The current time and date is \(formatted)."))
    #expect(defaulted.contains("helpful AI assistant"))
    #expect(!defaulted.contains(SystemPrompt.datetimeToken))
    #expect(SystemPrompt.defaultTemplate.contains("\n\nYou are a helpful AI assistant"))

    let custom = SystemPrompt.resolve(override: "Ready at %datetime%.", now: now, locale: locale, timeZone: timeZone)
    #expect(custom == "Ready at \(formatted).")
    let plain = SystemPrompt.resolve(override: "Stay brief.", now: now, locale: locale, timeZone: timeZone)
    #expect(plain == "Stay brief.")
}

@Test func systemPromptKeepsPresetInstructionOnTheEndpointBase() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let composed = SystemPrompt.composed(override: "", preset: .ask, now: now)
    #expect(composed.contains("helpful AI assistant"))
    #expect(composed.contains(Preset.ask.systemPrompt))
    let custom = SystemPrompt.composed(override: "Only JSON.", preset: .agent, now: now)
    #expect(custom.contains("Only JSON."))
    #expect(custom.contains(Preset.agent.systemPrompt))
}

@Test func systemPromptResolutionOrderUsesOverrideThenGlobalThenBuiltIn() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let locale = Locale(identifier: "en_US_POSIX")
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let formatted = SystemPrompt.formattedDateTime(now, locale: locale, timeZone: timeZone)

    let fromOverride = SystemPrompt.resolve(
        override: "Override at %datetime%.",
        global: "Global at %datetime%.",
        now: now,
        locale: locale,
        timeZone: timeZone
    )
    #expect(fromOverride == "Override at \(formatted).")

    let fromGlobal = SystemPrompt.resolve(
        override: "   ",
        global: "Global at %datetime%.",
        now: now,
        locale: locale,
        timeZone: timeZone
    )
    #expect(fromGlobal == "Global at \(formatted).")

    let fromBuiltIn = SystemPrompt.resolve(
        override: "",
        global: "\n",
        now: now,
        locale: locale,
        timeZone: timeZone
    )
    #expect(fromBuiltIn.hasPrefix("The current time and date is \(formatted)."))
    #expect(fromBuiltIn.contains("helpful AI assistant"))
    #expect(!fromBuiltIn.contains(SystemPrompt.datetimeToken))

    let composed = SystemPrompt.composed(
        override: "",
        global: "Stay on the global prompt.",
        preset: .agent,
        now: now,
        locale: locale,
        timeZone: timeZone
    )
    #expect(composed.contains("Stay on the global prompt."))
    #expect(composed.contains(Preset.agent.systemPrompt))
}

@Test func globalDefaultPromptPersistsAndEmptyFallsBackWithoutClearingEndpoint() {
    let suite = "aihud.tests.global-prompt"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)

    let first = SystemPrompt.loadGlobal(from: defaults)
    #expect(first == SystemPrompt.defaultTemplate)
    #expect(defaults.string(forKey: SystemPrompt.globalKey) == SystemPrompt.defaultTemplate)

    SystemPrompt.saveGlobal("Be terse at %datetime%.", to: defaults)
    #expect(SystemPrompt.loadGlobal(from: defaults) == "Be terse at %datetime%.")
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")

    SystemPrompt.saveGlobal("   ", to: defaults)
    #expect(SystemPrompt.loadGlobal(from: defaults) == SystemPrompt.defaultTemplate)
    #expect(defaults.string(forKey: SystemPrompt.globalKey) == SystemPrompt.defaultTemplate)
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}

@Test func catalogAlwaysIncludesOnDeviceRowAndRejectsRemoval() {
    let empty = ChatEndpointCatalog.migrate(
        stored: nil,
        defaultID: nil,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(empty.endpoints.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    #expect(empty.endpoints.filter { $0.id == ChatEndpointCatalog.onDeviceID }.count == 1)
    #expect(ChatEndpointCatalog.isOnDevice(empty.endpoints[0]))

    let cloud = ChatEndpoint(
        id: UUID(),
        name: "Work",
        completionsURL: "https://work.example/v1",
        model: "opus",
        systemPrompt: "Be brief"
    )
    let stored = try! JSONEncoder().encode([cloud])
    let loaded = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: cloud.id.uuidString,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(loaded.endpoints.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    #expect(loaded.endpoints.contains { $0.id == cloud.id })
    #expect(loaded.defaultID == cloud.id)

    let afterDelete = ChatEndpointCatalog.removing(ChatEndpointCatalog.onDeviceID, from: loaded.endpoints)
    #expect(afterDelete.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    #expect(afterDelete.contains { $0.id == cloud.id })
    #expect(afterDelete.filter { $0.id == ChatEndpointCatalog.onDeviceID }.count == 1)

    let afterCloudDelete = ChatEndpointCatalog.removing(cloud.id, from: loaded.endpoints)
    #expect(afterCloudDelete.contains { $0.id == ChatEndpointCatalog.onDeviceID })
    #expect(!afterCloudDelete.contains { $0.id == cloud.id })
}

@Test func selectingOnDeviceMakesTheNextSendOnDevice() {
    let cloud = ChatEndpoint(
        id: UUID(),
        name: "Work",
        completionsURL: "https://work.example/v1",
        model: "opus",
        systemPrompt: ""
    )
    let endpoints = ChatEndpointCatalog.ensuringOnDevice([cloud])
    let ready = SendTarget.ready(
        url: URL(string: "https://work.example/v1/chat/completions")!,
        model: "opus",
        apiKey: "sk-test",
        kind: .openaiCompletions
    )

    #expect(ChatEndpointCatalog.usesOnDevice(endpoints: endpoints, defaultID: ChatEndpointCatalog.onDeviceID))
    let onDevice = ChatRouting.decide(
        onDevice: ChatEndpointCatalog.usesOnDevice(
            endpoints: endpoints,
            defaultID: ChatEndpointCatalog.onDeviceID
        ),
        availability: .available,
        cloud: ready
    )
    #expect(onDevice == .onDevice)

    #expect(!ChatEndpointCatalog.usesOnDevice(endpoints: endpoints, defaultID: cloud.id))
    let cloudRoute = ChatRouting.decide(
        onDevice: ChatEndpointCatalog.usesOnDevice(endpoints: endpoints, defaultID: cloud.id),
        availability: .available,
        cloud: ready
    )
    #expect(cloudRoute == .cloud(ready))
}

@Test func onDeviceToggleMigratesToSelectedOnDeviceRow() {
    let cloud = ChatEndpoint(
        id: UUID(),
        name: "Work",
        completionsURL: "https://work.example/v1",
        model: "opus",
        systemPrompt: ""
    )
    let stored = try! JSONEncoder().encode([cloud])
    let migrated = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: cloud.id.uuidString,
        legacyURL: nil,
        legacyModel: nil,
        onDeviceWasEnabled: true
    )
    #expect(migrated.defaultID == ChatEndpointCatalog.onDeviceID)
    #expect(migrated.endpoints.contains { $0.id == cloud.id })
    #expect(ChatEndpointCatalog.usesOnDevice(endpoints: migrated.endpoints, defaultID: migrated.defaultID))

    let untouched = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: cloud.id.uuidString,
        legacyURL: nil,
        legacyModel: nil,
        onDeviceWasEnabled: false
    )
    #expect(untouched.defaultID == cloud.id)
    #expect(!ChatEndpointCatalog.usesOnDevice(endpoints: untouched.endpoints, defaultID: untouched.defaultID))
}

@Test func markdownRendersBlocksWithoutLeavingSourceMarkers() {
    let source = """
    ## Title
    This is **bold** and *italic* plus `code`.
    - First
    - Second

    ```swift
    let value = 1
    ```

    See [docs](https://example.com/secret).
    """
    let rendered = ReplyMarkdown.attributed(source)
    let text = String(rendered.characters)
    #expect(text.contains("Title"))
    #expect(!text.contains("## Title"))
    #expect(text.contains("bold"))
    #expect(!text.contains("**bold**"))
    #expect(text.contains("italic"))
    #expect(!text.contains("*italic*"))
    #expect(text.contains("code"))
    #expect(!text.contains("`code`"))
    #expect(text.contains("• First"))
    #expect(text.contains("• Second"))
    #expect(!text.contains("FirstSecond"))
    #expect(text.contains("let value = 1"))
    #expect(!text.contains("```"))
    #expect(text.contains("docs"))
    #expect(!text.contains("[docs]"))
    #expect(!text.contains("https://example.com/secret"))
    #expect(ReplyMarkdown.containsInline(rendered, .stronglyEmphasized))
    #expect(ReplyMarkdown.containsInline(rendered, .emphasized))
    #expect(ReplyMarkdown.containsInline(rendered, .code))
    #expect(ReplyMarkdown.containsCodeBlock(rendered))
    #expect(!ReplyMarkdown.containsLink(rendered))
}

@Test func markdownLeavesAnIncompleteFenceAsPlainText() {
    let source = "Hello\n```python\nprint(1"
    let rendered = ReplyMarkdown.attributed(source)
    let text = String(rendered.characters)
    #expect(text.contains("Hello"))
    #expect(text.contains("print(1"))
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

@Test func interactiveGlassStaysOffSoAClickDoesNotDistortTheCard() {
    #expect(!HUDMaterial.prefersInteractiveGlass(isControlBackdrop: true, osMajorVersion: 27))
    #expect(!HUDMaterial.prefersInteractiveGlass(isControlBackdrop: false, osMajorVersion: 27))
    #expect(!HUDMaterial.prefersInteractiveGlass(isControlBackdrop: true, osMajorVersion: 26))
}

@Test func glassContainerSpacingBatchesWithoutMergingNearbyPlates() {
    #expect(HUDMaterial.glassContainerSpacing == 0)
    #expect(HUDMaterial.glassContainerSpacing < HUDMetrics.controlSpacing)
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
    #expect(HUDMaterial.loadAmount(from: defaults) == 0.5)
    #expect(HUDMaterial.veilOpacity(glassAmount: HUDMaterial.loadAmount(from: defaults)) == 0.5)
    HUDMaterial.saveAmount(0.4, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 0.4)
    HUDMaterial.saveAmount(1, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 1)
    HUDMaterial.saveAmount(2, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 1)
    defaults.removePersistentDomain(forName: "aihud.tests.glass-amount")
}

@Test func onDeviceOffUsesTheCloudTarget() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test",
        kind: .openaiCompletions
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
        apiKey: "sk-test",
        kind: .openaiCompletions
    )
    let route = ChatRouting.decide(onDevice: true, availability: .available, cloud: ready)
    #expect(route == .onDevice)
}

@Test func onDeviceOnBlocksInsteadOfFallingBack() {
    let ready = SendTarget.ready(
        url: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o",
        apiKey: "sk-test",
        kind: .openaiCompletions
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
        apiKey: "sk-test",
        kind: .openaiCompletions
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

@Test func multilinePromptDefaultsOffAndDoesNotClearEndpointFields() {
    let suite = "aihud.tests.multiline-prompt"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    #expect(!PromptSettings.loadMultiline(from: defaults))
    PromptSettings.saveMultiline(true, to: defaults)
    #expect(PromptSettings.loadMultiline(from: defaults))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    PromptSettings.saveMultiline(false, to: defaults)
    #expect(!PromptSettings.loadMultiline(from: defaults))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}

@Test func promptHeightUsesFontMetricsAndCapsAtTenLines() {
    let font = NSFont.systemFont(ofSize: PromptLayout.fontSize)
    let line = PromptLayout.lineHeight(for: font)
    #expect(line >= ceil(font.boundingRectForFont.height))
    #expect(PromptLayout.fieldHeight(visibleLines: 1, font: font) == line)
    #expect(PromptLayout.fieldHeight(visibleLines: 10, font: font) == line * 10)
    #expect(PromptLayout.fieldHeight(visibleLines: 20, font: font) == line * 10)
    #expect(PromptLayout.rowHeight(visibleLines: 1, font: font) == HUDMetrics.rowHeight)
    #expect(PromptLayout.rowHeight(visibleLines: 2, font: font) == HUDMetrics.rowHeight + line)
    #expect(PromptLayout.rowHeight(visibleLines: 10, font: font) == HUDMetrics.rowHeight + line * 9)
    #expect(PromptLayout.rowHeight(visibleLines: 20, font: font) == PromptLayout.rowHeight(visibleLines: 10, font: font))
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

@Test func tableOmitsUnselectedPresetsOnAFreshLaunch() {
    let empty = ChatEndpointCatalog.migrate(
        stored: nil,
        defaultID: nil,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(empty.endpoints.count == 1)
    #expect(empty.endpoints[0].id == ChatEndpointCatalog.onDeviceID)
    #expect(ChatEndpointCatalog.isOnDevice(empty.endpoints[0]))
    for preset in ChatEndpointCatalog.cloudPresets {
        #expect(!empty.endpoints.contains { $0.presetID == preset.id })
    }

    let unused = ChatEndpointCatalog.cloudPresets.map { ChatEndpointCatalog.seededEndpoint($0) }
    let stored = try! JSONEncoder().encode(unused)
    let cleaned = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: unused.first?.id.uuidString,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(cleaned.endpoints.count == 1)
    #expect(cleaned.endpoints[0].id == ChatEndpointCatalog.onDeviceID)
    #expect(!cleaned.endpoints.contains { $0.presetID == "openai" })
}

@Test func catalogKeepsUserRowsAndExistingDefaultWhenSeeding() {
    let custom = ChatEndpoint(
        id: UUID(),
        name: "Home",
        completionsURL: "https://home.example/v1",
        model: "gpt-4o",
        systemPrompt: "Stay"
    )
    let stored = try! JSONEncoder().encode([custom])
    let loaded = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: custom.id.uuidString,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(loaded.defaultID == custom.id)
    #expect(loaded.endpoints.contains { $0.id == custom.id && $0.systemPrompt == "Stay" && $0.model == "gpt-4o" })
    #expect(!loaded.endpoints.contains { $0.presetID == "openai" })
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: loaded.endpoints, defaultID: loaded.defaultID)?.id == custom.id)
}

@Test func choosingAPresetFillsADraftAndSaveCreatesOnlyThatRow() {
    let table = ChatEndpointCatalog.ensuringOnDevice([])
    #expect(!table.contains { $0.presetID == "groq" })

    let draft = EndpointAddPolicy.draft(for: .preset("groq"))
    #expect(draft.name == "Groq")
    #expect(draft.completionsURL == "https://api.groq.com/openai/v1")
    #expect(draft.kind == .openaiCompatible)
    #expect(draft.presetID == "groq")
    #expect(draft.model.isEmpty)
    #expect(!table.contains { $0.id == draft.id })

    var toSave = draft
    toSave.model = "llama-3.3-70b"
    let saved = ChatEndpointCatalog.applyingSaved(toSave, to: table)
    #expect(saved.filter { $0.presetID == "groq" }.count == 1)
    #expect(saved.contains { $0.id == draft.id && $0.model == "llama-3.3-70b" })
    #expect(!saved.contains { $0.presetID == "openai" })
    #expect(saved.contains { $0.id == ChatEndpointCatalog.onDeviceID })

    let custom = EndpointAddPolicy.draft(for: .custom)
    #expect(custom.name.isEmpty)
    #expect(custom.completionsURL.isEmpty)
    #expect(custom.kind == .openaiCompatible)
    #expect(custom.presetID == nil)
}

@Test func catalogTagsLegacyOpenAIHostInsteadOfDuplicating() {
    let legacy = ChatEndpoint(
        id: UUID(),
        name: ChatEndpointCatalog.migratedName,
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-4o",
        systemPrompt: "Be brief"
    )
    let stored = try! JSONEncoder().encode([legacy])
    let loaded = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: legacy.id.uuidString,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(loaded.endpoints.filter { $0.presetID == "openai" }.count == 1)
    let openai = loaded.endpoints.first { $0.presetID == "openai" }
    #expect(openai?.id == legacy.id)
    #expect(openai?.model == "gpt-4o")
    #expect(openai?.systemPrompt == "Be brief")
    #expect(loaded.defaultID == legacy.id)
}

@Test func unusedSeedWithASecretOrPromptStays() {
    var keyed = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "openai" }!
    )
    let kept = ChatEndpointCatalog.pruningUnusedSeeds(
        [keyed],
        hasSecret: { $0 == keyed.id }
    )
    #expect(kept.contains { $0.id == keyed.id })

    keyed = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "groq" }!
    )
    keyed.systemPrompt = "Stay"
    let prompted = ChatEndpointCatalog.pruningUnusedSeeds([keyed])
    #expect(prompted.contains { $0.id == keyed.id && $0.systemPrompt == "Stay" })
}

@Test func highlightingARowDoesNotChangeDefaultOrVision() {
    let chat = UUID()
    let other = UUID()
    let highlighted = EndpointTablePolicy.apply(
        .highlight(other),
        defaultID: chat,
        visionID: nil
    )
    #expect(highlighted.defaultID == chat)
    #expect(highlighted.visionID == nil)
    #expect(highlighted.opensEditor == nil)

    let edited = EndpointTablePolicy.apply(
        .edit(other),
        defaultID: chat,
        visionID: nil
    )
    #expect(edited.defaultID == chat)
    #expect(edited.visionID == nil)
    #expect(edited.opensEditor == other)

    let madeDefault = EndpointTablePolicy.apply(
        .makeDefault(other),
        defaultID: chat,
        visionID: nil
    )
    #expect(madeDefault.defaultID == other)
    #expect(madeDefault.visionID == nil)
    #expect(madeDefault.opensEditor == nil)

    let onDevice = EndpointTablePolicy.apply(
        .makeDefault(ChatEndpointCatalog.onDeviceID),
        defaultID: chat,
        visionID: other
    )
    #expect(onDevice.defaultID == ChatEndpointCatalog.onDeviceID)
    #expect(onDevice.visionID == other)
}

@Test func saveRejectsAnIncompleteNewRow() {
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .openaiCompatible,
                name: "",
                completionsURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == "Add a name."
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .openaiCompatible,
                name: "Work",
                completionsURL: "",
                model: "gpt-4o",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == "Add a base URL."
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .anthropic,
                name: "Anthropic",
                completionsURL: "https://api.anthropic.com/v1",
                model: "",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == "Add a model id."
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .openaiCompatible,
                name: "Work",
                completionsURL: "https://work.example/v1",
                model: "opus",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == nil
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .chatgptSubscription,
                name: "ChatGPT",
                completionsURL: ChatGPTAuth.apiBase,
                model: "",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == "Sign in to ChatGPT."
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .chatgptSubscription,
                name: "ChatGPT",
                completionsURL: ChatGPTAuth.apiBase,
                model: "",
                isNew: true,
                hasChatGPTToken: true
            )
        ) == nil
    )
}

@Test func modelsURLJoinsBaseAndKeepsCleartextPolicy() {
    #expect(
        EndpointResolver.modelsURL(configured: "https://api.openai.com/v1")
            == .success(URL(string: "https://api.openai.com/v1/models")!)
    )
    #expect(
        EndpointResolver.modelsURL(configured: "https://api.openai.com/v1/models")
            == .success(URL(string: "https://api.openai.com/v1/models")!)
    )
    #expect(EndpointResolver.modelsURL(configured: "http://127.0.0.1:11434/v1").isSuccess)
    #expect(EndpointResolver.modelsURL(configured: "http://evil.example/v1") == .failure(.insecureHost))
    #expect(
        EndpointResolver.messagesURL(configured: "https://api.anthropic.com/v1")
            == .success(URL(string: "https://api.anthropic.com/v1/messages")!)
    )
    #expect(
        EndpointResolver.responsesURL(configured: "https://chatgpt.com/backend-api/codex")
            == .success(URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
    )
}

@Test func modelListParsingKeepsSavedIdAndTreatsEmptyAsFailure() {
    let openAI = ModelList.parseOpenAI(
        Data("""
        {"data":[{"id":"gpt-5.4"},{"id":"whisper-1"},{"id":"gpt-4o"},{"id":"gpt-5.4-2026-01-01"}]}
        """.utf8)
    )
    #expect(openAI.contains("gpt-5.4"))
    #expect(!openAI.contains("whisper-1"))
    #expect(!openAI.contains("gpt-4o"))
    #expect(!openAI.contains("gpt-5.4-2026-01-01"))

    let anthropic = ModelList.parseAnthropic(
        Data("""
        {"data":[{"type":"model","id":"claude-sonnet-4","display_name":"Sonnet 4","created_at":"2026-01-01"},{"type":"model","id":"claude-sonnet-5","display_name":"Sonnet 5","created_at":"2026-01-02"}],"has_more":false}
        """.utf8)
    )
    #expect(anthropic.contains("claude-sonnet-5"))
    #expect(!anthropic.contains("claude-sonnet-4"))

    let chatgpt = ModelList.parseChatGPT(
        Data("""
        {"models":[{"slug":"gpt-5.4"},{"slug":"hidden","visibility":"hide"}]}
        """.utf8)
    )
    #expect(chatgpt == ["gpt-5.4"])

    #expect(ModelList.selectModel(saved: "gpt-5.4", models: ["gpt-5.5", "gpt-5.4"]) == "gpt-5.4")
    #expect(ModelList.selectModel(saved: "gone", models: ["gpt-5.5", "gpt-5.4"]) == "gpt-5.5")
    #expect(ModelList.selectModel(saved: "typed-id", models: []) == "typed-id")
    #expect(ModelList.isFailed(models: []))

    var endpoint = ChatEndpoint(
        id: UUID(),
        name: "OpenAI",
        completionsURL: "https://api.openai.com/v1",
        model: "typed-id",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai",
        availableModels: ["kept"]
    )
    let failed = ModelList.apply(models: [], to: endpoint)
    #expect(failed.model == "typed-id")
    #expect(failed.availableModels == ["kept"])
    let listed = ModelList.apply(models: ["gpt-5.5", "gpt-5.4"], to: endpoint)
    #expect(listed.model == "gpt-5.5")
    #expect(listed.availableModels == ["gpt-5.5", "gpt-5.4"])
}

@Test func chatgptRowRoutesToResponsesNotCompletionsOrOnDevice() {
    let chatgpt = ChatEndpoint(
        id: UUID(),
        name: "ChatGPT",
        completionsURL: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .chatgptSubscription,
        presetID: "chatgpt"
    )
    let secret = ChatGPTAuth.serialize(
        ChatGPTAuth.Credential(refresh: "r", access: "a", expires: 9_999_999_999_999, accountId: "acct")
    )
    let target = ChatEndpointCatalog.target(
        endpoint: chatgpt,
        apiKey: secret,
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    guard case .ready(let url, let model, _, let kind) = target else {
        Issue.record("expected a ChatGPT target")
        return
    }
    #expect(kind == .chatgptResponses)
    #expect(model == "gpt-5.4")
    #expect(url.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
    #expect(
        ChatRouting.decide(onDevice: false, availability: .available, cloud: target) == .cloud(target)
    )
}

@Test func anthropicAndOpenAIRowsKeepTheirOwnSendPaths() {
    let anthropic = ChatEndpoint(
        id: UUID(),
        name: "Anthropic",
        completionsURL: "https://api.anthropic.com/v1",
        model: "claude-sonnet-5",
        systemPrompt: "",
        kind: .anthropic,
        presetID: "anthropic"
    )
    let openai = ChatEndpoint(
        id: UUID(),
        name: "OpenAI",
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai"
    )
    let anthropicTarget = ChatEndpointCatalog.target(
        endpoint: anthropic,
        apiKey: "sk-ant",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    let openaiTarget = ChatEndpointCatalog.target(
        endpoint: openai,
        apiKey: "sk-test",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    guard case .ready(let anthropicURL, _, _, let anthropicKind) = anthropicTarget else {
        Issue.record("expected Anthropic")
        return
    }
    guard case .ready(let openaiURL, _, _, let openaiKind) = openaiTarget else {
        Issue.record("expected OpenAI")
        return
    }
    #expect(anthropicKind == .anthropicMessages)
    #expect(anthropicURL.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(openaiKind == .openaiCompletions)
    #expect(openaiURL.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(openaiKind != .chatgptResponses)
}

@Test func visionUsesTheMarkedRowAndNotTheChatDefault() {
    let chat = ChatEndpoint(
        id: UUID(),
        name: "Chat",
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-4o",
        systemPrompt: ""
    )
    let vision = ChatEndpoint(
        id: UUID(),
        name: "Vision",
        completionsURL: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini",
        systemPrompt: ""
    )
    let setVision = EndpointTablePolicy.apply(
        .setVision(vision.id),
        defaultID: chat.id,
        visionID: nil
    )
    #expect(setVision.defaultID == chat.id)
    #expect(setVision.visionID == vision.id)

    let click = EndpointTablePolicy.apply(
        .highlight(vision.id),
        defaultID: chat.id,
        visionID: nil
    )
    #expect(click.visionID == nil)

    let noVision = ChatEndpointCatalog.target(
        endpoint: chat,
        apiKey: "chat",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: true,
        allowedCleartextHosts: []
    )
    guard case .ready(_, let chatModel, _, _) = noVision else {
        Issue.record("expected chat fallback when no vision row is marked")
        return
    }
    #expect(chatModel == "gpt-4o")

    let marked = ChatEndpointCatalog.target(
        endpoint: chat,
        apiKey: "chat",
        vision: ServiceCredentials(
            url: vision.completionsURL,
            model: vision.model,
            apiKey: "gem"
        ),
        hasImage: true,
        allowedCleartextHosts: []
    )
    guard case .ready(_, let visionModel, let visionKey, _) = marked else {
        Issue.record("expected the marked vision row")
        return
    }
    #expect(visionModel == "gemini")
    #expect(visionKey == "gem")

    let migrated = ChatEndpointCatalog.migrateVision(
        endpoints: [chat],
        visionID: nil,
        legacyURL: vision.completionsURL,
        legacyModel: vision.model
    )
    #expect(migrated.visionID != nil)
    #expect(migrated.endpoints.contains { $0.id == migrated.visionID && $0.model == "gemini" })
    #expect(migrated.endpoints.contains { $0.id == chat.id })
}

@Test func anthropicAndResponsesParsersReadTokens() {
    #expect(
        AnthropicParser.parse(line: "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}")
            == .token("Hi")
    )
    #expect(AnthropicParser.parse(line: "data: {\"type\":\"message_stop\"}") == .done)
    #expect(
        ResponsesParser.parse(line: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Yo\"}")
            == .token("Yo")
    )
    #expect(ResponsesParser.parse(line: "data: {\"type\":\"response.completed\"}") == .done)
    #expect(ResponsesParser.parse(line: "data: [DONE]") == .done)
}

@Test func chatgptCredentialParsesWithoutTreatingAnAPIKeyAsOAuth() {
    let credential = ChatGPTAuth.Credential(refresh: "r", access: "a", expires: 100, accountId: "acct")
    let json = ChatGPTAuth.serialize(credential)
    #expect(ChatGPTAuth.parse(json)?.accountId == "acct")
    #expect(ChatGPTAuth.parse("sk-live") == nil)
    #expect(!ChatGPTAuth.isFresh(credential, now: 200))
    let fresh = ChatGPTAuth.Credential(refresh: "r", access: "a", expires: 10_000, accountId: "acct")
    #expect(ChatGPTAuth.isFresh(fresh, now: 1))
}

private extension Result where Failure == EndpointError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
