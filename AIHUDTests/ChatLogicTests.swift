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
    #expect(text.contains("```python"))
    #expect(!ReplyMarkdown.containsCodeBlock(rendered))
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
    HUDMaterial.saveAmount(0, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 0)
    #expect(HUDMaterial.veilOpacity(glassAmount: HUDMaterial.loadAmount(from: defaults)) == 1)
    HUDMaterial.saveAmount(0.4, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 0.4)
    HUDMaterial.saveAmount(0.5, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 0.5)
    HUDMaterial.saveAmount(1, to: defaults)
    #expect(HUDMaterial.loadAmount(from: defaults) == 1)
    #expect(HUDMaterial.veilOpacity(glassAmount: HUDMaterial.loadAmount(from: defaults)) == 0)
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
    #expect(!ModelChoice.visionIsIncomplete(incomplete))
    #expect(!ModelChoice.visionIsIncomplete(blank))
    #expect(!ModelChoice.visionIsIncomplete(vision))
    let missingKey = ServiceCredentials(
        url: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini",
        apiKey: ""
    )
    #expect(ModelChoice.visionIsIncomplete(missingKey))
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

@Test func screenJPEGFallsToTheThirdPassWhenStillOverBudget() {
    var calls: [(Int, CGFloat)] = []
    let data = ScreenImage.choose { edge, quality in
        calls.append((edge, quality))
        return Data(count: ScreenImage.budget + 1)
    }
    #expect(calls.count == 3)
    #expect(calls[2].0 == 1280)
    #expect(calls[2].1 == 0.40)
    #expect(data.count == ScreenImage.budget + 1)
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
        defaultID: nil,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(cleaned.endpoints.count == 1)
    #expect(cleaned.endpoints[0].id == ChatEndpointCatalog.onDeviceID)
    #expect(!cleaned.endpoints.contains { $0.presetID == "openai" })

    let keptDefault = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: unused.first?.id.uuidString,
        legacyURL: nil,
        legacyModel: nil
    )
    #expect(keptDefault.endpoints.contains { $0.id == unused.first?.id })
    #expect(!keptDefault.endpoints.contains { $0.presetID == "groq" })
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

    let seededDefault = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "openai" }!
    )
    let keptDefault = ChatEndpointCatalog.pruningUnusedSeeds([seededDefault], defaultID: seededDefault.id)
    #expect(keptDefault.contains { $0.id == seededDefault.id })
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
}

@Test func onDeviceCannotBeOpenedForEdit() {
    let cloud = UUID()
    let blocked = EndpointTablePolicy.apply(
        .edit(ChatEndpointCatalog.onDeviceID),
        defaultID: cloud,
        visionID: nil
    )
    #expect(blocked.opensEditor == nil)
    #expect(blocked.defaultID == cloud)
    #expect(blocked.visionID == nil)

    let allowed = EndpointTablePolicy.apply(
        .edit(cloud),
        defaultID: ChatEndpointCatalog.onDeviceID,
        visionID: nil
    )
    #expect(allowed.opensEditor == cloud)
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
        ) == nil
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
    let click = EndpointTablePolicy.apply(
        .highlight(vision.id),
        defaultID: chat.id,
        visionID: nil
    )
    #expect(click.visionID == nil)
    #expect(click.opensEditor == nil)

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

@Test func parserHandlesStringErrorsInvalidJSONAndHTTPBodies() {
    #expect(SSEParser.parse(line: "data: not-json") == .skip)
    #expect(SSEParser.parse(line: "data: {\"error\":\"boom\"}") == .failure("boom"))
    #expect(SSEParser.parse(line: "data: {\"error\":{\"code\":1}}") == .failure("The request failed."))
    #expect(SSEParser.parse(line: "data: {\"error\":{\"message\":\"\"}}") == .failure("The request failed."))
    #expect(SSEParser.parse(line: "data: {\"error\":\"\"}") == .skip)
    #expect(SSEParser.parse(line: "data: {\"choices\":[]}") == .skip)
    #expect(SSEParser.errorMessage(from: Data("{\"error\":{\"message\":\"nope\"}}".utf8)) == "nope")
    #expect(SSEParser.errorMessage(from: Data("not json".utf8)) == nil)
}

@Test func anthropicParserSkipsNoiseAndReadsErrorsAndDone() {
    #expect(AnthropicParser.parse(line: ": ping") == .skip)
    #expect(AnthropicParser.parse(line: "") == .skip)
    #expect(AnthropicParser.parse(line: "event: message_start") == .skip)
    #expect(AnthropicParser.parse(line: "data: not-json") == .skip)
    #expect(AnthropicParser.parse(line: "data: [DONE]") == .done)
    #expect(AnthropicParser.parse(line: "data:[DONE]\r") == .done)
    #expect(AnthropicParser.parse(line: "data: {\"type\":\"error\"}") == .failure("The request failed."))
    #expect(AnthropicParser.parse(line: "data: {\"error\":{\"message\":\"rate\"}}") == .failure("rate"))
    #expect(
        AnthropicParser.parse(line: "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"\"}}")
            == .skip
    )
    #expect(AnthropicParser.parse(line: "data: {\"type\":\"message_start\"}") == .skip)
    #expect(AnthropicParser.parse(line: "data: {\"type\":\"message_stop\"}\r") == .done)
}

@Test func responsesFollowUpMarksAssistantHistoryAsOutputText() throws {
    let request = ChatRequest(
        url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
        model: "gpt-5.4",
        apiKey: "",
        messages: [
            OutboundMessage(role: "user", text: "hi", imageJPEGs: []),
            OutboundMessage(role: "assistant", text: "hello", imageJPEGs: []),
            OutboundMessage(role: "user", text: "again", imageJPEGs: []),
        ]
    )
    let data = try JSONEncoder().encode(ResponsesBody(request: request))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let input = try #require(object["input"] as? [[String: Any]])
    #expect(input.count == 3)
    #expect(input[0]["role"] as? String == "user")
    #expect(input[1]["role"] as? String == "assistant")
    #expect(input[2]["role"] as? String == "user")
    let firstUser = try #require(input[0]["content"] as? [[String: Any]])
    let assistant = try #require(input[1]["content"] as? [[String: Any]])
    let secondUser = try #require(input[2]["content"] as? [[String: Any]])
    #expect(firstUser[0]["type"] as? String == "input_text")
    #expect(assistant[0]["type"] as? String == "output_text")
    #expect(secondUser[0]["type"] as? String == "input_text")
}

@Test func responsesSingleTurnUserKeepsInputText() throws {
    let request = ChatRequest(
        url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
        model: "gpt-5.4",
        apiKey: "",
        messages: [
            OutboundMessage(role: "user", text: "hi", imageJPEGs: []),
        ]
    )
    let data = try JSONEncoder().encode(ResponsesBody(request: request))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let input = try #require(object["input"] as? [[String: Any]])
    let content = try #require(input[0]["content"] as? [[String: Any]])
    #expect(input.count == 1)
    #expect(input[0]["role"] as? String == "user")
    #expect(content[0]["type"] as? String == "input_text")
}

@Test func responsesParserHandlesIncompleteFailedAndEmptyDelta() {
    #expect(ResponsesParser.parse(line: ": ping") == .skip)
    #expect(ResponsesParser.parse(line: "") == .skip)
    #expect(ResponsesParser.parse(line: "data: not-json") == .skip)
    #expect(ResponsesParser.parse(line: "data: {\"type\":\"response.incomplete\"}") == .done)
    #expect(ResponsesParser.parse(line: "data: {\"type\":\"response.failed\"}") == .failure("The request failed."))
    #expect(ResponsesParser.parse(line: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"\"}") == .skip)
    #expect(ResponsesParser.parse(line: "data: {\"error\":\"nope\"}") == .failure("nope"))
    #expect(
        ResponsesParser.parse(line: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Yo\"}\r")
            == .token("Yo")
    )
}

@Test func chatgptAuthParsesAuthorizationInputAndRejectsStateMismatch() throws {
    #expect(throws: ChatGPTAuthError.message("Paste the authorization code to continue.")) {
        try ChatGPTAuth.parseAuthorizationInput("  ")
    }
    let fromURL = try ChatGPTAuth.parseAuthorizationInput(
        "http://localhost:1455/auth/callback?code=abc&state=st"
    )
    #expect(fromURL.code == "abc")
    #expect(fromURL.state == "st")
    let fromHash = try ChatGPTAuth.parseAuthorizationInput("thecode#thestate")
    #expect(fromHash.code == "thecode")
    #expect(fromHash.state == "thestate")
    #expect(throws: ChatGPTAuthError.message("Paste the authorization code to continue.")) {
        try ChatGPTAuth.parseAuthorizationInput("#only-state")
    }
    let plain = try ChatGPTAuth.parseAuthorizationInput("plaincode")
    #expect(plain.code == "plaincode")
    #expect(plain.state == nil)

    let session = ChatGPTAuth.ConnectSession(
        url: URL(string: "https://example.com")!,
        verifier: "v",
        state: "st"
    )
    try ChatGPTAuth.assertState(session: session, parsedState: nil)
    try ChatGPTAuth.assertState(session: session, parsedState: "st")
    #expect(throws: ChatGPTAuthError.message("This sign-in expired. Try connecting again.")) {
        try ChatGPTAuth.assertState(session: session, parsedState: "other")
    }
}

@Test func chatgptAuthReadsAccountAndResidencyFromJWT() {
    func jwt(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        var encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "aaa.\(encoded).sig"
    }
    let nested = jwt([
        "https://api.openai.com/auth": [
            "chatgpt_account_id": "acct-1",
            "chatgpt_compute_residency": "us"
        ]
    ])
    #expect(ChatGPTAuth.accountID(from: nested) == "acct-1")
    #expect(ChatGPTAuth.residency(from: nested) == "us")
    let direct = jwt([
        "chatgpt_account_id": "acct-2",
        "chatgpt_compute_residency": "no_constraint"
    ])
    #expect(ChatGPTAuth.accountID(from: direct) == "acct-2")
    #expect(ChatGPTAuth.residency(from: direct) == nil)
    let orgs = jwt(["organizations": [["id": "org-1"]]])
    #expect(ChatGPTAuth.accountID(from: orgs) == "org-1")
    #expect(ChatGPTAuth.accountID(from: "not-a-jwt") == nil)
    #expect(ChatGPTAuth.parse("{\"type\":\"oauth\"}") == nil)
    #expect(ChatGPTAuth.parse("{\"type\":\"oauth\",\"refresh\":\"\",\"access\":\"a\",\"expires\":1}") == nil)
    let emptyAccess = ChatGPTAuth.Credential(refresh: "r", access: "", expires: 9_999_999_999, accountId: nil)
    #expect(!ChatGPTAuth.isFresh(emptyAccess, now: 1))
    let connect = ChatGPTAuth.startConnect()
    #expect(connect.url.absoluteString.contains("client_id="))
    #expect(connect.url.absoluteString.contains("code_challenge_method=S256"))
    #expect(!connect.verifier.isEmpty)
    #expect(!connect.state.isEmpty)
}

@Test func joinKeepsExistingSuffixAndRejectsMissingHost() {
    #expect(
        EndpointResolver.messagesURL(configured: "https://api.anthropic.com/v1/messages")
            == .success(URL(string: "https://api.anthropic.com/v1/messages")!)
    )
    #expect(
        EndpointResolver.responsesURL(configured: "https://chatgpt.com/backend-api/codex/responses/")
            == .success(URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
    )
    #expect(EndpointResolver.completionsURL(configured: "http://localhost:8080/v1").isSuccess)
    #expect(EndpointResolver.completionsURL(configured: "http://[::1]:8080/v1").isSuccess)
    #expect(EndpointResolver.completionsURL(configured: "https://") == .failure(.unsupportedScheme))
    #expect(EndpointResolver.completionsURL(configured: "not a url") == .failure(.unsupportedScheme))
    #expect(EndpointResolver.modelsURL(configured: "ftp://127.0.0.1/v1") == .failure(.unsupportedScheme))
}

@Test func redirectRejectsAMissingHost() {
    let relative = URL(string: "/v1/chat/completions")!
    #expect(!RedirectPolicy.allows(originalHost: "api.openai.com", next: relative))
}

@Test func sendWithOnlyChipsAndStopWithoutTokens() {
    var session = Session()
    session.chips = [Chip(id: UUID(), name: "note.txt", payload: .text("hello"))]
    #expect(session.canSend)
    guard case .request(let messages) = session.send() else {
        Issue.record("expected a request")
        return
    }
    #expect(session.draft.isEmpty)
    #expect(session.chips.isEmpty)
    #expect(session.phase == .waiting)
    #expect(messages.last?.text.contains("[note.txt]") == true)
    #expect(session.send() == .ignored)

    session.stop()
    #expect(session.phase == .composing)
    #expect(session.displayAnswer.isEmpty)
    #expect(session.turns.isEmpty == false)
}

@Test func stopKeepsAPartialAndFinishIgnoresIdle() {
    var session = Session()
    session.draft = "Hi"
    _ = session.send()
    session.receiveToken("")
    #expect(session.phase == .waiting)
    session.receiveToken("Yo")
    session.receiveToken("")
    #expect(session.displayAnswer == "Yo")
    session.finish()
    #expect(session.phase == .finished)
    #expect(session.turns.last?.text == "Yo")
    session.receiveToken("late")
    session.finish()
    session.fail("late")
    session.stop()
    #expect(session.phase == .finished)
    #expect(session.displayAnswer == "Yo")
}

@Test func failRestoresChipsAndOutboundIncludesImages() {
    var session = Session()
    let jpeg = Data([0xFF, 0xD8, 0xFF])
    session.draft = "Look"
    session.chips = [Chip(id: UUID(), name: "shot.jpg", payload: .jpeg(jpeg))]
    guard case .request(let outbound) = session.send() else {
        Issue.record("expected a request")
        return
    }
    #expect(outbound.last?.imageJPEGs == [jpeg])
    #expect(outbound.last?.text == "Look")
    session.fail("The request timed out.")
    #expect(session.draft == "Look")
    #expect(session.chips.map(\.name) == ["shot.jpg"])
    #expect(session.phase == .failed("The request timed out."))

    session.draft = ""
    session.chips = []
    let attached = session.send(attachedJPEG: jpeg, attachmentName: "Screen")
    guard case .request(let withScreen) = attached else {
        Issue.record("expected a screen send")
        return
    }
    #expect(withScreen.last?.imageJPEGs == [jpeg])
    #expect(withScreen.last?.text == "Screen")
}

@Test func collapsedTranscriptKeepsTheLastAssistantRow() {
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi")
    session.finish()
    session.draft = "Again"
    _ = session.send()
    session.receiveToken("There")
    let collapsed = Transcript.rows(in: session, expanded: false)
    #expect(collapsed.map(\.text) == ["There"])
    #expect(collapsed.first?.live == true)
    session.finish()
    let done = Transcript.rows(in: session, expanded: false)
    #expect(done.map(\.text) == ["There"])
    #expect(done.allSatisfy { !$0.live })
    var idle = Session()
    #expect(Transcript.rows(in: idle, expanded: false).isEmpty)
}

@Test func markdownRendersNumberedListsHeadingsAndTildeFences() {
    let source = """
    # One
    ### Three
    * Star
    1. First
    2. Second

    ~~~python
    print(1)
    ~~~
    """
    let rendered = ReplyMarkdown.attributed(source)
    let text = String(rendered.characters)
    #expect(text.contains("One"))
    #expect(!text.contains("# One"))
    #expect(text.contains("Three"))
    #expect(!text.contains("### Three"))
    #expect(text.contains("• Star"))
    #expect(text.contains("1. First"))
    #expect(text.contains("2. Second"))
    #expect(text.contains("print(1)"))
    #expect(text.contains("python"))
    #expect(!text.contains("~~~"))
    #expect(ReplyMarkdown.containsCodeBlock(rendered))
}

@Test func promptLayoutClampsZeroLinesAndKeepsVerticalInsetNonNegative() {
    let font = NSFont.systemFont(ofSize: PromptLayout.fontSize)
    let line = PromptLayout.lineHeight(for: font)
    #expect(PromptLayout.fieldHeight(visibleLines: 0, font: font) == line)
    #expect(PromptLayout.rowHeight(visibleLines: 0, font: font) == HUDMetrics.rowHeight)
    #expect(PromptLayout.verticalInset(font: font) >= 0)
    let style = PromptLayout.paragraphStyle(for: font)
    #expect(style.minimumLineHeight == line)
    #expect(style.maximumLineHeight == line)
}

@Test func saveCreatesARowWithNameAndURLAndNoModelId() {
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .openaiCompatible,
                name: "Work",
                completionsURL: "https://work.example/v1",
                model: "",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == nil
    )
    let draft = EndpointAddPolicy.draft(for: .custom)
    var toSave = draft
    toSave.name = "Work"
    toSave.completionsURL = "https://work.example/v1"
    #expect(toSave.model.isEmpty)
    let saved = ChatEndpointCatalog.applyingSaved(toSave, to: ChatEndpointCatalog.ensuringOnDevice([]))
    #expect(saved.contains { $0.id == draft.id && $0.name == "Work" && $0.model.isEmpty })
}

@Test func chatAndVisionSelectionsPersistAsProviderAndModel() {
    let suite = "aihud.tests.chat-vision-selection"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let chat = ChatEndpoint(
        id: UUID(),
        name: "Chat",
        completionsURL: "https://api.openai.com/v1",
        model: "row-chat",
        systemPrompt: ""
    )
    let vision = ChatEndpoint(
        id: UUID(),
        name: "Vision",
        completionsURL: "https://vision.example/v1",
        model: "row-vision",
        systemPrompt: ""
    )
    ChatEndpointCatalog.save(
        endpoints: [chat, vision],
        defaultID: chat.id,
        visionID: vision.id,
        chatModelID: "picker-chat",
        visionModelID: "picker-vision",
        to: defaults
    )
    let loaded = ChatEndpointCatalog.load(from: defaults)
    #expect(loaded.defaultID == chat.id)
    #expect(loaded.chatModelID == "picker-chat")
    #expect(loaded.visionID == vision.id)
    #expect(loaded.visionModelID == "picker-vision")

    let text = ChatEndpointCatalog.target(
        endpoint: chat,
        apiKey: "sk-chat",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: [],
        modelID: loaded.chatModelID
    )
    guard case .ready(_, let chatModel, _, _) = text else {
        Issue.record("expected chat selection")
        defaults.removePersistentDomain(forName: suite)
        return
    }
    #expect(chatModel == "picker-chat")

    let image = ChatEndpointCatalog.target(
        endpoint: chat,
        apiKey: "sk-chat",
        vision: ServiceCredentials(
            url: vision.completionsURL,
            model: loaded.visionModelID,
            apiKey: "sk-vision"
        ),
        hasImage: true,
        allowedCleartextHosts: ["vision.example"],
        modelID: loaded.chatModelID
    )
    guard case .ready(_, let visionModel, let visionKey, _) = image else {
        Issue.record("expected vision selection")
        defaults.removePersistentDomain(forName: suite)
        return
    }
    #expect(visionModel == "picker-vision")
    #expect(visionKey == "sk-vision")

    let fallback = ChatEndpointCatalog.target(
        endpoint: chat,
        apiKey: "sk-chat",
        vision: ServiceCredentials(url: vision.completionsURL, model: "", apiKey: ""),
        hasImage: true,
        allowedCleartextHosts: ["vision.example"],
        modelID: "picker-chat"
    )
    guard case .ready(_, let fallbackModel, _, _) = fallback else {
        Issue.record("expected chat fallback when vision is unset")
        defaults.removePersistentDomain(forName: suite)
        return
    }
    #expect(fallbackModel == "picker-chat")

    let stored = try! JSONEncoder().encode([chat, vision])
    let migrated = ChatEndpointCatalog.migrate(
        stored: stored,
        defaultID: chat.id.uuidString,
        legacyURL: nil,
        legacyModel: nil,
        visionID: vision.id.uuidString
    )
    #expect(migrated.defaultID == chat.id)
    #expect(migrated.chatModelID == "row-chat")
    #expect(migrated.visionID == vision.id)
    #expect(migrated.visionModelID == "row-vision")
    defaults.removePersistentDomain(forName: suite)
}

@Test func modelsPaneIsLabeledModels() {
    #expect(SettingsPage.chat.title == "Models")
}

@Test func saveDoesNotRequireAKeyAndBlankChatGPTEditDoesNotWipe() {
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .openaiCompatible,
                name: "Work",
                completionsURL: "https://work.example/v1",
                model: "opus",
                isNew: false,
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
                isNew: false,
                hasChatGPTToken: false
            )
        ) == nil
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .onDevice,
                name: "",
                completionsURL: "",
                model: "",
                isNew: true,
                hasChatGPTToken: false
            )
        ) == nil
    )
    #expect(
        EndpointSavePolicy.rejection(
            EndpointDraft(
                kind: .chatgptSubscription,
                name: "",
                completionsURL: ChatGPTAuth.apiBase,
                model: "",
                isNew: false,
                hasChatGPTToken: true
            )
        ) == "Add a name."
    )
}

@Test func loopbackSendDoesNotRequireAKeyUnlessThePresetDoes() {
    let ollama = ChatEndpoint(
        id: UUID(),
        name: "Ollama",
        completionsURL: "http://127.0.0.1:11434/v1",
        model: "llama",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "ollama"
    )
    let ollamaTarget = ChatEndpointCatalog.target(
        endpoint: ollama,
        apiKey: "",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    guard case .ready(_, let model, let key, let kind) = ollamaTarget else {
        Issue.record("expected Ollama without a key")
        return
    }
    #expect(model == "llama")
    #expect(key.isEmpty)
    #expect(kind == .openaiCompletions)
    #expect(!ChatEndpointCatalog.requiresAPIKey(ollama))

    let unsloth = ChatEndpoint(
        id: UUID(),
        name: "Unsloth",
        completionsURL: "http://127.0.0.1:8888/v1",
        model: "local",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "unsloth"
    )
    let unslothTarget = ChatEndpointCatalog.target(
        endpoint: unsloth,
        apiKey: "",
        vision: ServiceCredentials(url: "", model: "", apiKey: ""),
        hasImage: false,
        allowedCleartextHosts: []
    )
    #expect(unslothTarget == .blocked("Add an API key in Settings"))
    #expect(ChatEndpointCatalog.requiresAPIKey(unsloth))
    #expect(!ChatEndpointCatalog.matchesHost(ollama.completionsURL, unsloth.completionsURL))
    #expect(ChatEndpointCatalog.matchesHost("http://127.0.0.1:11434/v1", "http://127.0.0.1:11434/v1/"))
}

@Test func emptyModelAndMissingChatGPTTokenBlockSend() {
    let openai = ChatEndpoint(
        id: UUID(),
        name: "OpenAI",
        completionsURL: "https://api.openai.com/v1",
        model: "  ",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai"
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: openai,
            apiKey: "sk-test",
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) == .blocked("Add a model id in Settings")
    )
    let chatgpt = ChatEndpoint(
        id: UUID(),
        name: "ChatGPT",
        completionsURL: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .chatgptSubscription,
        presetID: "chatgpt"
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: chatgpt,
            apiKey: "sk-live",
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) == .blocked("Sign in to ChatGPT in Settings")
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: openai,
            apiKey: "sk-test",
            vision: ServiceCredentials(url: "https://vision.example/v1", model: "", apiKey: ""),
            hasImage: true,
            allowedCleartextHosts: ["vision.example"],
            modelID: "gpt-4o"
        ) == .ready(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            model: "gpt-4o",
            apiKey: "sk-test",
            kind: .openaiCompletions
        )
    )
}

@Test func badURLBlocksSendAndOnDeviceWithoutVisionCannotBeTheCloudTarget() {
    let bad = ChatEndpoint(
        id: UUID(),
        name: "Bad",
        completionsURL: "ftp://example.com/v1",
        model: "x",
        systemPrompt: ""
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: bad,
            apiKey: "sk-test",
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) == .blocked("Check the base URL in Settings")
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: ChatEndpointCatalog.onDeviceEndpoint,
            apiKey: "",
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) == .blocked(ChatEndpointCatalog.missingEndpointMessage)
    )
    #expect(!ChatEndpointCatalog.requiresAPIKey(ChatEndpointCatalog.onDeviceEndpoint))
    #expect(!ChatEndpointCatalog.requiresAPIKey(
        ChatEndpoint(
            id: UUID(),
            name: "ChatGPT",
            completionsURL: ChatGPTAuth.apiBase,
            model: "",
            systemPrompt: "",
            kind: .chatgptSubscription,
            presetID: "chatgpt"
        )
    ))
}

@Test func unknownPresetDraftFallsBackToCustom() {
    let unknown = EndpointAddPolicy.draft(for: .preset("not-a-host"))
    #expect(unknown.name.isEmpty)
    #expect(unknown.completionsURL.isEmpty)
    #expect(unknown.kind == .openaiCompatible)
    #expect(unknown.presetID == nil)
}

@Test func endpointLabelsAndFlagsDescribeOnDeviceAndChatGPT() {
    let onDevice = ChatEndpointCatalog.onDeviceEndpoint
    #expect(onDevice.hostLabel == "On this Mac")
    #expect(onDevice.modelLabel == "Apple Intelligence")
    #expect(onDevice.urlIsFixed)
    #expect(!onDevice.usesChatGPTAuth)
    let chatgpt = EndpointAddPolicy.draft(for: .preset("chatgpt"))
    #expect(chatgpt.urlIsFixed)
    #expect(chatgpt.usesChatGPTAuth)
    #expect(chatgpt.kind == .chatgptSubscription)
    #expect(chatgpt.completionsURL == ChatGPTAuth.apiBase)
    let openai = EndpointAddPolicy.draft(for: .preset("openai"))
    #expect(!openai.urlIsFixed)
    #expect(!openai.usesChatGPTAuth)
    #expect(openai.hostLabel == "api.openai.com")
}

@Test func unusedSeedWithAvailableModelsOrVisionMarkStays() {
    var listed = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "openai" }!
    )
    listed.availableModels = ["gpt-5.4"]
    let keptListed = ChatEndpointCatalog.pruningUnusedSeeds([listed])
    #expect(keptListed.contains { $0.id == listed.id })

    let seed = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "groq" }!
    )
    let keptVision = ChatEndpointCatalog.pruningUnusedSeeds([seed], visionID: seed.id)
    #expect(keptVision.contains { $0.id == seed.id })
}

@Test func deletingTheDefaultFallsBackAndVisionCanBeOnDevice() {
    let cloud = ChatEndpoint(
        id: UUID(),
        name: "Work",
        completionsURL: "https://work.example/v1",
        model: "opus",
        systemPrompt: ""
    )
    let endpoints = ChatEndpointCatalog.ensuringOnDevice([cloud])
    let afterDelete = ChatEndpointCatalog.removing(cloud.id, from: endpoints)
    #expect(ChatEndpointCatalog.resolvedDefault(endpoints: afterDelete, defaultID: cloud.id)?.id == ChatEndpointCatalog.onDeviceID)
    #expect(ChatEndpointCatalog.resolvedVision(endpoints: endpoints, visionID: ChatEndpointCatalog.onDeviceID)?.id == ChatEndpointCatalog.onDeviceID)
    #expect(ChatEndpointCatalog.matchesHost("https://api.openai.com/v1", "https://api.openai.com/v1/"))
    #expect(!ChatEndpointCatalog.matchesHost("https://api.openai.com/v1", "https://api.anthropic.com/v1"))
}

@Test func storedRowsWithoutKindDecodeOnDeviceAndOpenAI() throws {
    let onDeviceJSON = """
    [{"id":"00000000-0000-4000-A1D0-000000000001","name":"On-device","completionsURL":"","model":""}]
    """
    let onDevice = try JSONDecoder().decode([ChatEndpoint].self, from: Data(onDeviceJSON.utf8))
    #expect(onDevice[0].kind == .onDevice)
    #expect(onDevice[0].systemPrompt.isEmpty)
    let cloudID = UUID()
    let cloudJSON = """
    [{"id":"\(cloudID.uuidString)","name":"Work","completionsURL":"https://api.openai.com/v1","model":"gpt-4o"}]
    """
    let cloud = try JSONDecoder().decode([ChatEndpoint].self, from: Data(cloudJSON.utf8))
    #expect(cloud[0].kind == .openaiCompatible)
    #expect(cloud[0].availableModels.isEmpty)
}

@Test func modelListParsingRejectsMalformedPayloadsAndKeepsASavedId() {
    #expect(ModelList.parseOpenAI(Data("not-json".utf8)).isEmpty)
    #expect(ModelList.parseAnthropic(Data("{}".utf8)).isEmpty)
    #expect(ModelList.parseChatGPT(Data("{\"models\":[{\"slug\":\"\"},{\"slug\":\"ok\"}]}".utf8)) == ["ok"])
    #expect(ModelList.shouldIgnoreOpenAI("text-embedding-3"))
    #expect(ModelList.shouldIgnoreOpenAI("tts-1"))
    #expect(ModelList.shouldIgnoreAnthropic("claude-sonnet-4"))
    #expect(!ModelList.shouldIgnoreAnthropic("claude-sonnet-5"))
    let ranked = ModelList.sortByRecency(["gpt-5.4", "gpt-5.6", "gpt-5.5"])
    #expect(ranked.first == "gpt-5.6")
    var endpoint = ChatEndpoint(
        id: UUID(),
        name: "OpenAI",
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai"
    )
    let listed = ModelList.apply(models: ["gpt-5.5", "gpt-5.4"], to: endpoint)
    #expect(listed.model == "gpt-5.4")
    #expect(listed.availableModels == ["gpt-5.5", "gpt-5.4"])
}

@Test func chatRoutingMessagesMatchAvailability() {
    #expect(ChatRouting.message(for: .available) == nil)
    #expect(ChatRouting.message(for: .notEnabled) == ChatRouting.appleIntelligenceOff)
    #expect(ChatRouting.message(for: .notEligible) == ChatRouting.macNotEligible)
    #expect(ChatRouting.message(for: .notReady) == ChatRouting.modelNotReady)
    #expect(ChatRouting.message(for: .other) == ChatRouting.modelUnavailable)
}

@Test func chatgptVisionCredentialsNeedOAuthNotAnAPIKey() {
    let chat = ServiceCredentials(url: "https://api.openai.com/v1", model: "gpt-4o", apiKey: "chat")
    let chatgpt = ServiceCredentials(
        url: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        apiKey: "sk-live",
        kind: .chatgptSubscription
    )
    #expect(!chatgpt.isComplete)
    #expect(ModelChoice.pick(chat: chat, vision: chatgpt, hasImage: true) == chat)
    let secret = ChatGPTAuth.serialize(
        ChatGPTAuth.Credential(refresh: "r", access: "a", expires: 9_999_999_999, accountId: "acct")
    )
    let signedIn = ServiceCredentials(
        url: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        apiKey: secret,
        kind: .chatgptSubscription
    )
    #expect(signedIn.isComplete)
    #expect(ModelChoice.pick(chat: chat, vision: signedIn, hasImage: true) == signedIn)
}

@Test func attachmentAllowsTheFourthFileAndRejectsUnreadableImages() {
    let fourth = AttachmentPolicy.prepare(data: Data("ok".utf8), filename: "note.md", existingCount: 3)
    guard case .success(let chip) = fourth, case .text("ok") = chip.payload else {
        Issue.record("expected the fourth text file")
        return
    }
    #expect(chip.name == "note.md")
    #expect(
        AttachmentPolicy.prepare(data: Data([0x00, 0x01, 0x02]), filename: "dot.png", existingCount: 0)
            == .failure(.unreadableImage)
    )
}

@Test func devEndpointFileRequiresEveryField() {
    #expect(!DevEndpointFile(model: "", completionsURL: "https://api.openai.com/v1", apiKey: "sk").isUsable)
    #expect(!DevEndpointFile(model: "gpt", completionsURL: "  ", apiKey: "sk").isUsable)
    #expect(!DevEndpointFile(model: "gpt", completionsURL: "https://api.openai.com/v1", apiKey: "").isUsable)
    #expect(DevEndpointFile(model: "gpt", completionsURL: "https://api.openai.com/v1", apiKey: "sk").isUsable)
}

@Test func hudModelMenuSelectsChatWithoutTouchingVision() {
    let chat = UUID()
    let vision = UUID()
    let nextProvider = UUID()
    let current = ChatModelSelection(
        chatID: chat,
        chatModelID: "old-chat",
        visionID: vision,
        visionModelID: "old-vision"
    )
    let next = HUDModelMenu.selecting(
        providerID: nextProvider,
        modelID: "gpt-5.5",
        in: current
    )
    #expect(next.chatID == nextProvider)
    #expect(next.chatModelID == "gpt-5.5")
    #expect(next.visionID == vision)
    #expect(next.visionModelID == "old-vision")

    let onDevice = HUDModelMenu.selecting(
        providerID: ChatEndpointCatalog.onDeviceID,
        modelID: "ignored",
        in: current
    )
    #expect(onDevice.chatID == ChatEndpointCatalog.onDeviceID)
    #expect(onDevice.chatModelID == "")
    #expect(onDevice.visionID == vision)
    #expect(onDevice.visionModelID == "old-vision")
}

@Test func hudIdleMarkFollowsTheChatPreset() {
    #expect(HUDIdleMark.usesTemplate)
    #expect(HUDIdleMark.tintHex == "FFFFFF")
    #expect(HUDIdleMark.red == 1 && HUDIdleMark.green == 1 && HUDIdleMark.blue == 1)

    let expected: [String: ProviderLogoKind] = [
        "openai": .openai,
        "anthropic": .anthropic,
        "chatgpt": .openai,
        "openrouter": .openrouter,
        "venice": .venice,
        "moonshot": .moonshot,
        "zai": .zai,
        "deepseek": .deepseek,
        "alibaba_cloud": .alibaba,
        "siliconflow": .siliconflow,
        "cohere": .cohere,
        "groq": .groq,
        "xai": .xai,
        "together": .together,
        "fireworks": .fireworks,
        "cerebras": .cerebras,
        "mistral": .mistral,
        "meta": .meta,
        "lmstudio": .lmstudio,
        "ollama": .ollama,
        "unsloth": .unsloth
    ]
    for preset in ChatEndpointCatalog.cloudPresets {
        let kind = HUDModelMenu.logo(for: ChatEndpointCatalog.seededEndpoint(preset))
        #expect(kind == expected[preset.id])
        #expect(kind.imageName.hasSuffix("Logo"))
    }

    let anthropic = ChatEndpoint(
        id: UUID(),
        name: "Work Claude",
        completionsURL: "https://api.anthropic.com/v1",
        model: "claude-opus-4-8",
        systemPrompt: "",
        kind: .anthropic,
        presetID: "anthropic"
    )
    #expect(HUDModelMenu.logo(for: anthropic) == .anthropic)

    let chatgpt = ChatEndpoint(
        id: UUID(),
        name: "Codex",
        completionsURL: "https://chatgpt.com/backend-api/codex",
        model: "",
        systemPrompt: "",
        kind: .chatgptSubscription,
        presetID: "chatgpt"
    )
    #expect(HUDModelMenu.logo(for: chatgpt) == .openai)
    #expect(HUDModelMenu.logo(for: chatgpt).imageName == "OpenAILogo")

    let openaiHost = ChatEndpoint(
        id: UUID(),
        name: "Not the display name",
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-5.5",
        systemPrompt: ""
    )
    #expect(HUDModelMenu.logo(for: openaiHost) == .openai)

    let custom = ChatEndpoint(
        id: UUID(),
        name: "Hermes",
        completionsURL: "http://100.93.227.31:8080/v1",
        model: "local",
        systemPrompt: ""
    )
    #expect(HUDModelMenu.logo(for: custom) == .axiom)
    #expect(HUDModelMenu.logo(for: custom).imageName == "AxiomLogo")
    #expect(HUDModelMenu.logo(for: ChatEndpointCatalog.onDeviceEndpoint) == .appleIntelligence)
    #expect(HUDModelMenu.logo(for: ChatEndpointCatalog.onDeviceEndpoint).systemSymbolName == "apple.intelligence")
    #expect(NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil)
    #expect(
        HUDModelMenu.idleSlot(
            dictating: false,
            override: nil,
            endpoint: ChatEndpointCatalog.onDeviceEndpoint
        ) == .logo(.appleIntelligence)
    )
    #expect(
        HUDModelMenu.idleSlot(
            dictating: true,
            override: nil,
            endpoint: ChatEndpointCatalog.onDeviceEndpoint
        ) == .waveform
    )
}

@Test func hudModelMenuListsSavedRowsAndStoredModels() throws {
    let groq = ChatEndpointCatalog.cloudPresets.first { $0.id == "groq" }!
    let saved = ChatEndpoint(
        id: UUID(),
        name: "Office",
        completionsURL: "https://api.anthropic.com/v1",
        model: "claude-sonnet",
        systemPrompt: "",
        kind: .anthropic,
        presetID: "anthropic",
        availableModels: ["claude-opus-4-8", "claude-sonnet"]
    )
    let empty = ChatEndpoint(
        id: UUID(),
        name: "Empty",
        completionsURL: "https://api.groq.com/openai/v1",
        model: "",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "groq"
    )
    let storedOnly = ChatEndpoint(
        id: UUID(),
        name: "Stored",
        completionsURL: "https://api.openai.com/v1",
        model: "kept-id",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai"
    )
    let items = HUDModelMenu.items(
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, saved, empty, storedOnly],
        chatID: storedOnly.id,
        chatModelID: "picker-chat",
        secret: { id in
            if id == saved.id || id == storedOnly.id { return "sk-live" }
            return ""
        }
    )
    #expect(items.map(\.providerID) == [
        ChatEndpointCatalog.onDeviceID,
        saved.id,
        storedOnly.id
    ])
    #expect(items.contains { $0.title == groq.name } == false)
    #expect(items.contains { $0.providerID == empty.id } == false)
    let onDevice = try #require(items.first)
    #expect(onDevice.models == [
        HUDModelMenu.ModelRow(id: "", title: "Apple Intelligence", enabled: true)
    ])
    let listed = try #require(items.first { $0.providerID == saved.id })
    #expect(listed.models.map(\.id) == ["claude-opus-4-8", "claude-sonnet"])
    let kept = try #require(items.first { $0.providerID == storedOnly.id })
    #expect(kept.models == [
        HUDModelMenu.ModelRow(id: "picker-chat", title: "picker-chat", enabled: true)
    ])
}

@Test func hudMenuOmitsChatGPTWithoutATokenAndAPIKeyRowsWithoutAKey() {
    let chatgpt = ChatEndpoint(
        id: UUID(),
        name: "ChatGPT",
        completionsURL: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .chatgptSubscription,
        presetID: "chatgpt"
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
    let custom = ChatEndpoint(
        id: UUID(),
        name: "Hermes",
        completionsURL: "http://100.93.227.31:8080/v1",
        model: "local",
        systemPrompt: ""
    )
    let omitted = HUDModelMenu.items(
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, chatgpt, openai, custom],
        chatID: openai.id,
        chatModelID: "gpt-5.4",
        secret: { _ in "" },
        onDeviceReady: true
    )
    #expect(omitted.map(\.providerID) == [ChatEndpointCatalog.onDeviceID])
    #expect(omitted.contains { $0.providerID == chatgpt.id } == false)
    #expect(omitted.contains { $0.providerID == openai.id } == false)
    #expect(omitted.contains { $0.providerID == custom.id } == false)

    let unavailable = HUDModelMenu.items(
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, chatgpt],
        chatID: nil,
        chatModelID: "",
        secret: { _ in "" },
        onDeviceReady: false
    )
    #expect(unavailable.isEmpty)
}

@Test func hudMenuIncludesSignedInChatGPTAndSelectingItDoesNotAskToSignIn() {
    let chatgpt = ChatEndpoint(
        id: UUID(),
        name: "ChatGPT",
        completionsURL: ChatGPTAuth.apiBase,
        model: "gpt-5.4",
        systemPrompt: "",
        kind: .chatgptSubscription,
        presetID: "chatgpt",
        availableModels: ["gpt-5.4"]
    )
    let vision = UUID()
    let secret = ChatGPTAuth.serialize(
        ChatGPTAuth.Credential(refresh: "r", access: "a", expires: 9_999_999_999, accountId: "acct")
    )
    let items = HUDModelMenu.items(
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, chatgpt],
        chatID: ChatEndpointCatalog.onDeviceID,
        chatModelID: "",
        secret: { id in id == chatgpt.id ? secret : "" }
    )
    #expect(items.map(\.providerID) == [ChatEndpointCatalog.onDeviceID, chatgpt.id])

    let current = ChatModelSelection(
        chatID: ChatEndpointCatalog.onDeviceID,
        chatModelID: "",
        visionID: vision,
        visionModelID: "old-vision"
    )
    let pick = HUDModelMenu.picking(
        providerID: chatgpt.id,
        modelID: "gpt-5.4",
        in: current,
        secret: secret
    )
    #expect(pick.selection.chatID == chatgpt.id)
    #expect(pick.selection.chatModelID == "gpt-5.4")
    #expect(pick.selection.visionID == vision)
    #expect(pick.selection.visionModelID == "old-vision")
    #expect(pick.errorMessage == nil)
    #expect(
        ChatEndpointCatalog.target(
            endpoint: chatgpt,
            apiKey: secret,
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) != .blocked("Sign in to ChatGPT in Settings")
    )
    #expect(
        ChatEndpointCatalog.target(
            endpoint: chatgpt,
            apiKey: secret,
            vision: ServiceCredentials(url: "", model: "", apiKey: ""),
            hasImage: false,
            allowedCleartextHosts: []
        ) != .blocked("Sign in to ChatGPT.")
    )
}

@Test func cardHeightGrowsByTheErrorLine() {
    #expect(HUDLayout.cardHeight(hasErrorLine: false) == HUDMetrics.minCardHeight)
    #expect(HUDLayout.errorLineHeight > 0)
    #expect(
        HUDLayout.cardHeight(hasErrorLine: true)
            == HUDMetrics.minCardHeight + HUDLayout.errorLineHeight
    )
}

@Test func singleLineKeystrokeFlickerDoesNotChangeHeight() {
    let previous: CGFloat = 248
    #expect(
        HUDLayout.settledHeight(proposed: 249, previous: previous, lineCount: 1, multiline: false)
            == previous
    )
    #expect(
        HUDLayout.settledHeight(proposed: 247.25, previous: previous, lineCount: 1, multiline: false)
            == previous
    )
    let idle = HUDMetrics.minCardHeight
    let withError = HUDLayout.cardHeight(hasErrorLine: true)
    #expect(
        HUDLayout.settledHeight(proposed: withError, previous: idle, lineCount: 1, multiline: false)
            == withError
    )
}

@Test func multilineLineIncreaseChangesHeight() {
    let previous: CGFloat = 248
    let line = PromptLayout.lineHeight(for: PromptLayout.font())
    let proposed = previous + line
    #expect(
        HUDLayout.settledHeight(proposed: proposed, previous: previous, lineCount: 2, multiline: true)
            == proposed
    )
    #expect(
        HUDLayout.settledHeight(proposed: previous + 1, previous: previous, lineCount: 2, multiline: true)
            == previous
    )
}

@Test func pinningKeepsTheTopEdgeFixedWhenHeightGrows() {
    let current = NSRect(x: 80, y: 120, width: HUDMetrics.cardWidth, height: 108)
    let next = HUDLayout.framePinnedTop(current: current, height: 200)
    #expect(next.maxY == current.maxY)
    #expect(next.height == 200)
    #expect(next.origin.x == current.origin.x)
    #expect(next.width == HUDMetrics.cardWidth)
}

private extension Result where Failure == EndpointError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
