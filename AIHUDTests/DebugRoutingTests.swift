import Foundation
import Testing
@testable import AIHUD

@Test func debugCommandsMapStringsToPhases() {
    #expect(DebugRouting.phase(for: "composing-empty") == .composing)
    #expect(DebugRouting.phase(for: "composing-draft") == .composing)
    #expect(DebugRouting.phase(for: "waiting") == .waiting)
    #expect(DebugRouting.phase(for: "streaming") == .streaming)
    #expect(DebugRouting.phase(for: "finished") == .finished)
    #expect(DebugRouting.phase(for: "failed") == .failed(DebugRouting.timedOut))
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
    #expect(session.turns.contains { $0.role == .user })
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

@Test func debugLaunchFlagIsOffUnlessRequested() {
    #expect(!DebugRouting.enabled(by: ["AIHUD"]))
    #expect(!DebugRouting.enabled(by: ["AIHUD", "--show"]))
    #expect(DebugRouting.enabled(by: ["AIHUD", "--debug"]))
    #expect(DebugRouting.initialCommand(from: ["--debug-state=failed"]) == "failed")
    #expect(DebugRouting.initialCommand(from: ["--debug-state", "dictate-on"]) == "dictate-on")
    #expect(DebugRouting.phase(for: DebugRouting.initialCommand(from: ["--debug-state=streaming"]) ?? "") == .streaming)
}

@Test func enablingDebugDoesNotClearEndpointOrWake() {
    let suite = "aihud.tests.debug-persist"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    VoiceSettings.saveWakeOnAxiom(false, to: defaults)
    VoiceSettings.savePauseToSend(false, to: defaults)
    DebugSettings.saveEnabled(true, to: defaults)
    #expect(defaults.bool(forKey: DebugSettings.enabledKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    #expect(!defaults.bool(forKey: VoiceSettings.wakeOnAxiomKey))
    #expect(!defaults.bool(forKey: VoiceSettings.pauseToSendKey))
    DebugSettings.saveEnabled(false, to: defaults)
    #expect(!defaults.bool(forKey: DebugSettings.enabledKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}
