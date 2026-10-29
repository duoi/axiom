import Foundation
import Testing
@testable import Axiom

@Test func debugCommandsMapStringsToPhases() {
    #expect(DebugRouting.phase(for: "composing-empty") == .composing)
    #expect(DebugRouting.phase(for: "composing-draft") == .composing)
    #expect(DebugRouting.phase(for: "waiting") == .waiting)
    #expect(DebugRouting.phase(for: "streaming") == .streaming)
    #expect(DebugRouting.phase(for: "finished") == .finished)
    #expect(DebugRouting.phase(for: "markdown-reply") == .finished)
    #expect(DebugRouting.phase(for: "second-turn") == .finished)
    #expect(DebugRouting.phase(for: "failed") == .failed(DebugRouting.timedOut))
    #expect(DebugRouting.phase(for: "missing-endpoint") == .failed(ChatEndpointCatalog.missingEndpointMessage))
    #expect(DebugRouting.phase(for: "ask") == nil)
    #expect(DebugRouting.phase(for: "make-key") == nil)
    #expect(DebugRouting.phase(for: "reset") == .composing)
    #expect(DebugRouting.phase(for: "not-a-command") == nil)
}

@Test func debugComposingEmptyClearsTheDraft() {
    var session = Session()
    session.draft = "leftover"
    session = DebugRouting.apply("composing-empty", to: session)
    #expect(session.phase == .composing)
    #expect(session.draft.isEmpty)
    #expect(session.displayAnswer.isEmpty)
    #expect(session.turns.isEmpty)
    #expect(!session.showsStop)
}

@Test func debugComposingDraftSetsPromptText() {
    let session = DebugRouting.apply("composing-draft", to: Session())
    #expect(session.phase == .composing)
    #expect(session.draft == DebugRouting.draft)
    #expect(session.canSend)
}

@Test func debugWaitingShowsStopWithoutAnAnswer() {
    let session = DebugRouting.apply("waiting", to: Session())
    #expect(session.phase == .waiting)
    #expect(session.displayAnswer.isEmpty)
    #expect(session.showsStop)
    #expect(session.showsAnswer)
    #expect(session.draft == DebugRouting.draft)
    #expect(session.turns.contains { $0.role == .user })
}

@Test func debugInFlightPromptKeepsDraftForShimmer() {
    let session = DebugRouting.apply("in-flight-prompt", to: Session())
    #expect(session.phase == .waiting)
    #expect(session.draft == DebugRouting.draft)
    #expect(!PromptInFlightPolicy.isEditable(phase: session.phase))
}

@Test func debugStreamingKeepsAPartialAnswer() {
    let session = DebugRouting.apply("streaming", to: Session())
    #expect(session.phase == .streaming)
    #expect(session.displayAnswer == DebugRouting.partial)
    #expect(session.showsStop)
}

@Test func debugFinishedKeepsTheReply() {
    let session = DebugRouting.apply("finished", to: Session())
    #expect(session.phase == .finished)
    #expect(session.displayAnswer == DebugRouting.reply)
    #expect(!session.showsStop)
    #expect(session.turns.contains { $0.role == .assistant })
}

@Test func debugMarkdownReplyInjectsAFenceAndList() {
    let session = DebugRouting.apply("markdown-reply", to: Session())
    #expect(session.phase == .finished)
    #expect(session.displayAnswer == DebugRouting.markdownReply)
    #expect(session.displayAnswer.contains("```swift"))
    #expect(session.displayAnswer.contains("- First"))
    #expect(session.turns.contains { $0.role == .assistant && $0.text == DebugRouting.markdownReply })
}

@Test func debugPhaseCommandsClearStatusLines() {
    var snapshot = DebugRouting.apply("mic-denied", to: DebugSnapshot())
    snapshot = DebugRouting.apply("generic-failure", to: snapshot)
    snapshot = DebugRouting.apply("failed", to: snapshot)
    #expect(snapshot.session.phase == .failed(DebugRouting.timedOut))
    #expect(snapshot.voiceStatus == nil)
    #expect(snapshot.screenNotice == nil)
}

@Test func debugFailedUsesRealisticTimeoutCopy() {
    let session = DebugRouting.apply("failed", to: Session())
    #expect(session.phase == .failed(DebugRouting.timedOut))
    #expect(session.errorMessage == DebugRouting.timedOut)
    #expect(session.draft == DebugRouting.draft)
    #expect(session.turns.isEmpty)
    #expect(!session.showsStop)
}

@Test func unknownDebugCommandLeavesTheSessionAlone() {
    var session = Session()
    session.draft = "keep me"
    session = DebugRouting.apply("nope", to: session)
    #expect(session.draft == "keep me")
    #expect(session.phase == .composing)
}

@Test func debugResetReturnsTheIdleCard() {
    var snapshot = DebugRouting.apply("streaming", to: DebugSnapshot())
    snapshot = DebugRouting.apply("dictate-on", to: snapshot)
    snapshot = DebugRouting.apply("arm-screen", to: snapshot)
    snapshot = DebugRouting.apply("add-chip", to: snapshot)
    snapshot = DebugRouting.apply("mic-denied", to: snapshot)
    snapshot = DebugRouting.apply("generic-failure", to: snapshot)
    snapshot = DebugRouting.apply("logo-openai", to: snapshot)
    snapshot = DebugRouting.apply("multiline-on", to: snapshot)
    snapshot = DebugRouting.apply("history-on", to: snapshot)
    snapshot = DebugRouting.apply("reset", to: snapshot)
    #expect(snapshot.session.phase == .composing)
    #expect(snapshot.session.draft.isEmpty)
    #expect(snapshot.session.turns.isEmpty)
    #expect(snapshot.session.chips.isEmpty)
    #expect(snapshot.session.errorMessage == nil)
    #expect(!snapshot.dictating)
    #expect(!snapshot.captureArmed)
    #expect(snapshot.voiceStatus == nil)
    #expect(snapshot.screenNotice == nil)
    #expect(snapshot.logoOverride == nil)
    #expect(snapshot.captureTargetOverride == nil)
    #expect(snapshot.multilineOverride == nil)
    #expect(!snapshot.historyExpanded)
}

@Test func debugToolbarCommandsStayOnTheCurrentPhase() {
    var snapshot = DebugRouting.apply("composing-draft", to: DebugSnapshot())
    snapshot = DebugRouting.apply("ask", to: snapshot)
    #expect(snapshot.session.preset == .ask)
    #expect(snapshot.session.phase == .composing)
    snapshot = DebugRouting.apply("agent", to: snapshot)
    #expect(snapshot.session.preset == .agent)
    snapshot = DebugRouting.apply("arm-screen", to: snapshot)
    #expect(snapshot.captureArmed)
    snapshot = DebugRouting.apply("disarm-screen", to: snapshot)
    #expect(!snapshot.captureArmed)
    snapshot = DebugRouting.apply("dictate-on", to: snapshot)
    #expect(snapshot.dictating)
    #expect(snapshot.session.phase == .composing)
    snapshot = DebugRouting.apply("dictate-off", to: snapshot)
    #expect(!snapshot.dictating)
    snapshot = DebugRouting.apply("add-chip", to: snapshot)
    #expect(snapshot.session.chips.map(\.name) == [DebugRouting.chipName])
}

@Test func debugAddChipClearsAFailedPhaseAndDoesNotDuplicate() {
    var snapshot = DebugRouting.apply("failed", to: DebugSnapshot())
    snapshot = DebugRouting.apply("add-chip", to: snapshot)
    #expect(snapshot.session.phase == .composing)
    #expect(snapshot.session.chips.map(\.name) == [DebugRouting.chipName])
    #expect(snapshot.session.errorMessage == nil)
    snapshot = DebugRouting.apply("add-chip", to: snapshot)
    #expect(snapshot.session.chips.count == 1)
}

@Test func debugStatusLinesDoNotPromptAndDoNotChangePhase() {
    var snapshot = DebugRouting.apply("composing-draft", to: DebugSnapshot())
    snapshot = DebugRouting.apply("mic-denied", to: snapshot)
    #expect(snapshot.voiceStatus == VoiceStatusCopy.micDenied)
    #expect(snapshot.session.phase == .composing)
    snapshot = DebugRouting.apply("speech-denied", to: snapshot)
    #expect(snapshot.voiceStatus == VoiceStatusCopy.speechDenied)
    snapshot = DebugRouting.apply("generic-failure", to: snapshot)
    #expect(snapshot.screenNotice == DebugRouting.genericFailure)
    #expect(snapshot.session.phase == .composing)
    snapshot = DebugRouting.apply("clear-status", to: snapshot)
    #expect(snapshot.voiceStatus == nil)
    #expect(snapshot.screenNotice == nil)
}

@Test func debugFocusCommandsDoNotChangePhase() {
    var snapshot = DebugRouting.apply("finished", to: DebugSnapshot())
    snapshot = DebugRouting.apply("resign-key", to: snapshot)
    #expect(snapshot.session.phase == .finished)
    #expect(snapshot.wantsCardKey == false)
    snapshot = DebugRouting.apply("make-key", to: snapshot)
    #expect(snapshot.wantsCardKey == true)
    #expect(snapshot.session.phase == .finished)
}

@Test func cardMenuShowsDebugOnlyWhenDevModeIsOn() {
    #expect(HUDCardMenu.items(debugEnabled: false) == [.settings])
    #expect(HUDCardMenu.items(debugEnabled: true) == [.settings, .debug])
    #expect(HUDCardMenu.title(for: .settings) == "Settings")
    #expect(HUDCardMenu.title(for: .debug) == "Debug")
}

@Test @MainActor func debugToolsStayOffUntilTurnedOnInAbout() {
    let store = EndpointStore.isolated()
    #expect(store.debugToolsEnabled == false)
    #expect(store.showsDebug(arguments: ["Axiom"]) == false)
    #expect(store.showsDebug(arguments: ["Axiom", "--show", "--debug-state=reply-overflow"]) == false)
    // A developer launch still opens Debug.
    #expect(store.showsDebug(arguments: ["Axiom", "--debug"]))
    store.debugToolsEnabled = true
    #expect(store.showsDebug(arguments: ["Axiom"]))
}

@Test @MainActor func debugDoesNotOpenOrTurnItselfOnWhileOff() {
    let store = EndpointStore.isolated()
    let hud = HUDController(store: store)
    defer { hud.panel.orderOut(nil) }
    hud.openDebug()
    #expect(hud.debugWindow == nil)
    #expect(store.debugToolsEnabled == false)
}

@Test func debugLaunchFlagIsOffUnlessRequested() {
    #expect(!DebugRouting.enabled(by: ["Axiom"]))
    #expect(!DebugRouting.enabled(by: ["Axiom", "--show"]))
    #expect(DebugRouting.enabled(by: ["Axiom", "--debug"]))
    #expect(DebugRouting.initialCommand(from: ["--debug-state=failed"]) == "failed")
    #expect(DebugRouting.initialCommand(from: ["--debug-state", "dictate-on"]) == "dictate-on")
    #expect(DebugRouting.initialCommand(from: ["--debug-state="]) == nil)
    #expect(DebugRouting.initialCommand(from: ["--debug-state", ""]) == nil)
    #expect(DebugRouting.initialCommand(from: ["Axiom"]) == nil)
    #expect(DebugRouting.phase(for: DebugRouting.initialCommand(from: ["--debug-state=streaming"]) ?? "") == .streaming)
    #expect(DebugRouting.initialCommand(from: ["--debug-state=logo-anthropic"]) == "logo-anthropic")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=logo-openai"]) == "logo-openai")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=second-turn"]) == "second-turn")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=stream-sun"]) == "stream-sun")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=reply-overflow"]) == "reply-overflow")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=stream-line"]) == "stream-line")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=upper-extension"]) == "upper-extension")
    #expect(DebugRouting.phase(for: "logo-anthropic") == nil)
    #expect(DebugRouting.phase(for: "second-turn") == .finished)
    #expect(DebugRouting.phase(for: "stream-sun") == .finished)
    #expect(DebugRouting.parse("stream-sun") == .streamSun)
    #expect(DebugRouting.phase(for: "reply-10") == .finished)
    #expect(DebugRouting.phase(for: "reply-20") == .finished)
    #expect(DebugRouting.phase(for: "reply-overflow") == .finished)
    #expect(DebugRouting.parse("reply-overflow") == .replyOverflow)
    #expect(DebugRouting.liveStreamText(for: .replyOverflow) == DebugRouting.numberedReply(lines: 40))
    #expect(DebugRouting.phase(for: "arm-window") == nil)
    #expect(DebugRouting.parse("not-a-command") == nil)
    #expect(DebugRouting.logoKind(from: "logo-nope") == nil)
}

@Test func debugLogoFlagsParseWithoutChangingChatOrVision() {
    #expect(DebugRouting.logoKind(from: "logo-anthropic") == .anthropic)
    #expect(DebugRouting.logoKind(from: "logo-openai") == .openai)
    #expect(DebugRouting.logoKind(from: "logo-chatgpt") == .openai)
    #expect(DebugRouting.logoKind(from: "logo-axiom") == .axiom)
    #expect(DebugRouting.logoKind(from: "logo-on-device") == .appleIntelligence)
    #expect(DebugRouting.logoKind(from: "logo-apple") == .appleIntelligence)
    for choice in DebugRouting.logoChoices {
        #expect(DebugRouting.logoKind(from: choice.command) == choice.kind)
    }
    #expect(DebugRouting.logoChoices.contains { $0.command == "logo-on-device" && $0.kind == .appleIntelligence })
    #expect(DebugRouting.logoChoices.contains { $0.command == "logo-axiom" && $0.kind == .axiom })

    let chatID = UUID()
    let visionID = UUID()
    let current = ChatModelSelection(
        chatID: chatID,
        chatModelID: "kept-chat",
        visionID: visionID,
        visionModelID: "kept-vision"
    )
    var snapshot = DebugSnapshot()
    snapshot = DebugRouting.apply("logo-anthropic", to: snapshot)
    #expect(snapshot.logoOverride == .anthropic)
    #expect(snapshot.session.phase == .composing)
    #expect(snapshot.session.errorMessage == nil)
    #expect(snapshot.session.errorMessage != "Sign in to ChatGPT in Settings")
    #expect(snapshot.session.errorMessage != "Sign in to ChatGPT.")
    #expect(
        DebugChatApply.readyPick(
            logo: snapshot.logoOverride ?? .anthropic,
            endpoints: [ChatEndpointCatalog.onDeviceEndpoint],
            current: current,
            secret: { _ in "" },
            onDeviceReady: false
        ) == nil
    )

    snapshot = DebugRouting.apply("logo-openai", to: snapshot)
    #expect(snapshot.logoOverride == .openai)
    #expect(current.chatID == chatID)
    #expect(current.chatModelID == "kept-chat")
    #expect(current.visionID == visionID)
    #expect(current.visionModelID == "kept-vision")

    snapshot = DebugRouting.apply("logo-on-device", to: snapshot)
    #expect(snapshot.logoOverride == .appleIntelligence)
    #expect(snapshot.session.phase == .composing)
    #expect(current.chatID == chatID)
    #expect(current.chatModelID == "kept-chat")
    #expect(current.visionID == visionID)
    #expect(current.visionModelID == "kept-vision")
    snapshot = DebugRouting.apply("logo-apple", to: snapshot)
    #expect(snapshot.logoOverride == .appleIntelligence)
}

@Test func debugLogoOverrideDoesNotReplaceTheWaveform() {
    let anthropic = ChatEndpointCatalog.seededEndpoint(
        ChatEndpointCatalog.cloudPresets.first { $0.id == "anthropic" }!
    )
    #expect(
        HUDModelMenu.idleSlot(dictating: true, override: .openai, endpoint: anthropic)
            == .waveform
    )
    #expect(
        HUDModelMenu.idleSlot(dictating: false, override: .openai, endpoint: anthropic)
            == .logo(.openai)
    )
    #expect(
        HUDModelMenu.idleSlot(dictating: false, override: nil, endpoint: anthropic)
            == .logo(.anthropic)
    )
    var snapshot = DebugRouting.apply("logo-anthropic", to: DebugSnapshot())
    snapshot = DebugRouting.apply("dictate-on", to: snapshot)
    #expect(snapshot.logoOverride == .anthropic)
    #expect(snapshot.dictating)
    #expect(
        HUDModelMenu.idleSlot(
            dictating: snapshot.dictating,
            override: snapshot.logoOverride,
            endpoint: ChatEndpointCatalog.onDeviceEndpoint
        ) == .waveform
    )
}

@Test func debugSecondTurnKeepsTheFinishedReply() {
    let snapshot = DebugRouting.apply("second-turn", to: DebugSnapshot())
    #expect(snapshot.session.phase == .finished)
    #expect(snapshot.session.displayAnswer == DebugRouting.longReply)
    #expect(snapshot.session.displayAnswer != DebugRouting.reply)
    #expect(snapshot.session.draft == DebugRouting.followUp)
    #expect(snapshot.session.turns.contains { $0.role == .assistant && $0.text == DebugRouting.longReply })
    #expect(snapshot.session.canSend)
}

@Test func debugStreamSunReplaysTokensOntoTheWaitingTurn() {
    let snapshot = DebugRouting.apply("stream-sun", to: DebugSnapshot())
    #expect(snapshot.session.phase == .finished)
    #expect(snapshot.session.displayAnswer == DebugRouting.liveStreamReply)
    #expect(snapshot.session.turns.contains { $0.role == .user })
    #expect(snapshot.session.turns.contains { $0.role == .assistant && $0.text == DebugRouting.liveStreamReply })
}

@Test func debugNumberedRepliesKeepWrappedLineCounts() {
    let ten = DebugRouting.apply("reply-10", to: DebugSnapshot())
    #expect(ten.session.phase == .finished)
    #expect(ten.session.displayAnswer == DebugRouting.numberedReply(lines: 10))
    #expect(HUDLayout.wrappedReplyLines(ten.session.displayAnswer) == 10)

    let twenty = DebugRouting.apply("reply-20", to: DebugSnapshot())
    #expect(HUDLayout.wrappedReplyLines(twenty.session.displayAnswer) == 20)

    let overflow = DebugRouting.apply("reply-overflow", to: DebugSnapshot())
    #expect(overflow.session.phase == .finished)
    #expect(overflow.session.displayAnswer == DebugRouting.numberedReply(lines: 40))
    #expect(HUDLayout.wrappedReplyLines(overflow.session.displayAnswer) == 40)
    #expect(HUDLayout.replyVisibleLines(40) == 30)
}

@Test func debugCardLayoutStatesMapSnapshotsAndIgnoreUnknownValues() {
    #expect(DebugRouting.initialCommand(from: ["--debug-state=stream-line"]) == "stream-line")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=stream-multi"]) == "stream-multi")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=lower-extension"]) == "lower-extension")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=upper-extension"]) == "upper-extension")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=reply-overflow"]) == "reply-overflow")
    #expect(DebugRouting.initialCommand(from: ["--debug-state=expanded-conversation"]) == "expanded-conversation")
    #expect(DebugRouting.parse("not-a-real-debug-state") == nil)
    #expect(DebugRouting.phase(for: "not-a-real-debug-state") == nil)

    var leftover = DebugSnapshot()
    leftover.session.draft = "keep me"
    leftover = DebugRouting.apply("totally-unknown", to: leftover)
    #expect(leftover.session.draft == "keep me")
    #expect(leftover.session.phase == .composing)

    let streamLine = DebugRouting.apply("stream-line", to: DebugSnapshot())
    #expect(DebugRouting.parse("stream-line") == .streamLine)
    #expect(streamLine.session.phase == .streaming)
    #expect(streamLine.session.displayAnswer == DebugRouting.streamLineReply)
    #expect(HUDLayout.wrappedReplyLines(streamLine.session.displayAnswer) == 1)
    #expect(streamLine.historyExpanded == false)
    #expect(DebugRouting.liveStreamText(for: .streamLine) == DebugRouting.streamLineReply)
    #expect(DebugRouting.liveStreamFinishes(.streamLine) == false)

    let streamMulti = DebugRouting.apply("stream-multi", to: DebugSnapshot())
    #expect(streamMulti.session.phase == .streaming)
    #expect(streamMulti.session.displayAnswer == DebugRouting.streamMultiReply)
    let multiLines = HUDLayout.wrappedReplyLines(streamMulti.session.displayAnswer)
    #expect(multiLines > 1)
    #expect(multiLines < 15)
    #expect(streamMulti.historyExpanded == false)
    #expect(DebugRouting.liveStreamText(for: .streamMulti) == DebugRouting.streamMultiReply)
    #expect(DebugRouting.liveStreamFinishes(.streamMulti) == false)

    let lower = DebugRouting.apply("lower-extension", to: DebugSnapshot())
    #expect(lower.session.phase == .finished)
    #expect(HUDLayout.wrappedReplyLines(lower.session.displayAnswer) == 15)
    #expect(lower.historyExpanded == false)

    let upper = DebugRouting.apply("upper-extension", to: DebugSnapshot())
    #expect(upper.session.phase == .finished)
    #expect(HUDLayout.wrappedReplyLines(upper.session.displayAnswer) == 30)
    #expect(upper.historyExpanded == false)

    let overflow = DebugRouting.apply("reply-overflow", to: DebugSnapshot())
    #expect(overflow.session.phase == .finished)
    #expect(HUDLayout.wrappedReplyLines(overflow.session.displayAnswer) == 40)
    #expect(overflow.historyExpanded == false)

    let expanded = DebugRouting.apply("expanded-conversation", to: DebugSnapshot())
    #expect(expanded.historyExpanded)
    #expect(expanded.session.phase == .finished)
    #expect(!expanded.session.displayAnswer.isEmpty)
    #expect(expanded.session.turns.contains { $0.role == .user })
    #expect(expanded.session.turns.contains { $0.role == .assistant })
    #expect(expanded.session.turns.filter { $0.role == .user }.count >= 3)
    let transcript = expanded.session.turns.map(\.text).joined(separator: "\n")
    #expect(transcript.split(separator: "\n").count > HUDLayout.replyMaxLines)
}

@Test func debugArmWindowAndMultilineDoNotClearTheSession() {
    var snapshot = DebugRouting.apply("composing-draft", to: DebugSnapshot())
    snapshot = DebugRouting.apply("arm-window", to: snapshot)
    #expect(snapshot.captureArmed)
    #expect(snapshot.captureTargetOverride == .window)
    #expect(snapshot.session.phase == .composing)
    snapshot = DebugRouting.apply("arm-screen", to: snapshot)
    #expect(snapshot.captureTargetOverride == .screen)
    snapshot = DebugRouting.apply("multiline-on", to: snapshot)
    #expect(snapshot.multilineOverride == true)
    #expect(snapshot.session.draft == DebugRouting.draft)
    snapshot = DebugRouting.apply("history-on", to: snapshot)
    #expect(snapshot.historyExpanded)
}

@Test func debugErrorVariantsStayInsideTheCard() {
    var snapshot = DebugRouting.apply("missing-endpoint", to: DebugSnapshot())
    #expect(snapshot.session.phase == .failed(ChatEndpointCatalog.missingEndpointMessage))
    snapshot = DebugRouting.apply("missing-key", to: snapshot)
    #expect(snapshot.session.errorMessage == "Add an API key in Settings")
    snapshot = DebugRouting.apply("sign-in", to: snapshot)
    #expect(snapshot.session.errorMessage == "Sign in to ChatGPT in Settings")
    snapshot = DebugRouting.apply("logo-openai", to: snapshot)
    #expect(snapshot.logoOverride == .openai)
    #expect(snapshot.session.errorMessage == "Sign in to ChatGPT in Settings")
}

@Test func debugApplyChatModelNeedsAReadySavedRow() {
    let anthropic = ChatEndpoint(
        id: UUID(),
        name: "Work Claude",
        completionsURL: "https://api.anthropic.com/v1",
        model: "claude-opus-4-8",
        systemPrompt: "",
        kind: .anthropic,
        presetID: "anthropic"
    )
    let current = ChatModelSelection(
        chatID: ChatEndpointCatalog.onDeviceID,
        chatModelID: "",
        visionID: UUID(),
        visionModelID: "kept-vision"
    )
    #expect(
        DebugChatApply.readyPick(
            logo: .anthropic,
            endpoints: [ChatEndpointCatalog.onDeviceEndpoint, anthropic],
            current: current,
            secret: { _ in "" }
        ) == nil
    )
    let pick = DebugChatApply.readyPick(
        logo: .anthropic,
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, anthropic],
        current: current,
        secret: { id in id == anthropic.id ? "sk-live" : "" }
    )
    #expect(pick?.chatID == anthropic.id)
    #expect(pick?.chatModelID == "claude-opus-4-8")
    #expect(pick?.visionID == current.visionID)
    #expect(pick?.visionModelID == "kept-vision")
}

@Test func enablingDebugDoesNotClearEndpointOrWake() {
    let suite = "aihud.tests.debug-persist"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    let provider = UUID(uuidString: "00000000-0000-4000-A1D0-00000000ABCD")!
    let row = ChatEndpoint(
        id: provider,
        name: "Kept",
        completionsURL: "https://api.openai.com/v1",
        model: "gpt-4o",
        systemPrompt: "",
        kind: .openaiCompatible,
        presetID: "openai"
    )
    ChatEndpointCatalog.save(
        endpoints: [ChatEndpointCatalog.onDeviceEndpoint, row],
        defaultID: provider,
        visionID: provider,
        chatModelID: "gpt-4o",
        visionModelID: "gpt-4o-mini",
        to: defaults
    )
    VoiceSettings.saveWakeOnAxiom(false, to: defaults)
    VoiceSettings.savePauseToSend(false, to: defaults)
    DebugSettings.saveEnabled(true, to: defaults)
    _ = DebugRouting.apply("logo-anthropic", to: DebugSnapshot())
    _ = DebugRouting.apply("reset", to: DebugSnapshot())
    #expect(defaults.bool(forKey: DebugSettings.enabledKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    #expect(defaults.string(forKey: ChatEndpointCatalog.defaultIDKey) == provider.uuidString)
    #expect(defaults.string(forKey: ChatEndpointCatalog.chatModelIDKey) == "gpt-4o")
    #expect(defaults.string(forKey: ChatEndpointCatalog.visionIDKey) == provider.uuidString)
    #expect(defaults.string(forKey: ChatEndpointCatalog.visionModelIDKey) == "gpt-4o-mini")
    #expect(!defaults.bool(forKey: VoiceSettings.wakeOnAxiomKey))
    #expect(!defaults.bool(forKey: VoiceSettings.pauseToSendKey))
    DebugSettings.saveEnabled(false, to: defaults)
    #expect(!defaults.bool(forKey: DebugSettings.enabledKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    #expect(defaults.string(forKey: ChatEndpointCatalog.defaultIDKey) == provider.uuidString)
    #expect(defaults.string(forKey: ChatEndpointCatalog.chatModelIDKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}

@Test func debugPlanClassifiesCommandsWithoutMutatingStoredEndpoints() {
    var snapshot = DebugSnapshot()
    snapshot.session.draft = "keep me"
    let unknown = DebugRouting.plan(command: "not-a-command", snapshot: snapshot)
    if case .apply(let next) = unknown.kind {
        #expect(next.session.draft == "keep me")
    } else {
        Issue.record("unknown commands should apply the current snapshot")
    }
    #expect(unknown.shimmer == nil)

    let transcript = DebugRouting.plan(command: "open-transcript", snapshot: snapshot)
    #expect(transcript.kind == .openTranscript)

    let shimmer = DebugRouting.plan(command: "shimmer-white-sweep", snapshot: snapshot)
    #expect(shimmer.shimmer == .whiteSweep)
    if case .apply(let next) = shimmer.kind {
        #expect(next.session.phase == .waiting)
    } else {
        Issue.record("shimmer commands should apply the in-flight snapshot")
    }

    let retired = DebugRouting.plan(command: "shimmer-grok", snapshot: snapshot)
    #expect(retired.shimmer == nil)

    let bogusShimmer = DebugRouting.plan(command: "shimmer-nope", snapshot: snapshot)
    #expect(bogusShimmer.shimmer == nil)
    if case .apply(let next) = bogusShimmer.kind {
        #expect(next.session.draft == "keep me")
    } else {
        Issue.record("unknown shimmer names should leave the snapshot alone")
    }

    let flash = DebugRouting.plan(command: "flash-highlight", snapshot: snapshot)
    #expect(flash.kind == .flashHighlight)

    let inflight = DebugRouting.plan(command: "in-flight-prompt", snapshot: snapshot)
    #expect(inflight.shimmer == nil)

    let stream = DebugRouting.plan(command: "stream-line", snapshot: snapshot)
    if case .liveStream(let text, let finish) = stream.kind {
        #expect(text == DebugRouting.streamLineReply)
        #expect(!finish)
    } else {
        Issue.record("stream-line should be a live stream")
    }
}

@Test func demoPromptComesFromItsLaunchArgument() {
    #expect(DebugRouting.demoPrompt(from: ["Axiom", "--demo-prompt=What is Liquid Glass?"]) == "What is Liquid Glass?")
    #expect(DebugRouting.demoPrompt(from: ["Axiom", "--demo-prompt="]) == nil)
    #expect(DebugRouting.demoPrompt(from: ["Axiom", "--show"]) == nil)
}
