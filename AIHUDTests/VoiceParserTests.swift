import AppKit
import Foundation
import Testing
@testable import AIHUD

@Test func wakeReadsRemainderAfterAxiom() {
    let wake = VoiceParser.wake(in: "axiom what is the total mass of the sun")
    #expect(wake?.remainder == "what is the total mass of the sun")
}

@Test func spokenCommaDoesNotStayInTheRemainder() {
    let wake = VoiceParser.wake(in: "Axiom, what is the total mass of the sun?")
    #expect(wake?.remainder == "what is the total mass of the sun?")
}

@Test func axiomaticDoesNotWake() {
    #expect(VoiceParser.wake(in: "axiomatic") == nil)
}

@Test func axiomWakeIsCaseInsensitiveAndStripsLeadingPunctuation() {
    #expect(VoiceParser.wake(in: "AXIOM hello")?.remainder == "hello")
    #expect(VoiceParser.wake(in: "Axiom... wait")?.remainder == "wait")
    #expect(VoiceParser.wake(in: "hey Axiom, draft this")?.remainder == "draft this")
}

@Test func axDoesNotWake() {
    #expect(VoiceParser.wake(in: "ax") == nil)
    #expect(VoiceParser.wake(in: "axi") == nil)
}

@Test func growingTranscriptReplacesTheTail() {
    let first = VoiceParser.applyTranscript(base: "hello", transcript: "world", isFinal: false)
    #expect(first.display == "hello world")
    #expect(first.base == "hello")
    let second = VoiceParser.applyTranscript(base: first.base, transcript: "world peace", isFinal: false)
    #expect(second.display == "hello world peace")
    #expect(second.base == "hello")
}

@Test func finalizedTranscriptCommitsIntoTheBase() {
    let committed = VoiceParser.applyTranscript(base: "hello", transcript: "world peace", isFinal: true)
    #expect(committed.display == "hello world peace")
    #expect(committed.base == "hello world peace")
}

@Test func axiomSentenceYieldsTheQuestionAsDraft() {
    let spoken = "axiom what is the total mass of the sun"
    #expect(VoiceParser.draftText(from: spoken) == "what is the total mass of the sun")
    let volatile = VoiceParser.applyTranscript(
        base: "",
        transcript: VoiceParser.draftText(from: spoken),
        isFinal: false
    )
    #expect(volatile.display == "what is the total mass of the sun")
    let finalized = VoiceParser.applyTranscript(
        base: "",
        transcript: VoiceParser.draftText(from: spoken),
        isFinal: true
    )
    #expect(finalized.display == "what is the total mass of the sun")
    #expect(finalized.base == "what is the total mass of the sun")
}

@Test func axiomMustBeAtTheStart() {
    #expect(VoiceParser.wake(in: "the axiom of choice") == nil)
}

@Test func heyAxiomWakes() {
    let wake = VoiceParser.wake(in: "hey axiom")
    #expect(wake?.remainder == "")
}

@Test func pauseToSendOffNeverSends() {
    let send = VoiceParser.shouldAutoSend(
        optionOn: false,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .composing,
        dictating: true
    )
    #expect(!send)
}

@Test func pauseToSendOnWaitsForTheSilenceBuffer() {
    let tooSoon = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer - 0.1,
        phase: .composing,
        dictating: true
    )
    #expect(!tooSoon)
    let ready = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .composing,
        dictating: true
    )
    #expect(ready)
}

@Test func pauseToSendNeedsANonEmptyDraft() {
    let empty = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "   ",
        silentFor: VoiceParser.silenceBuffer,
        phase: .composing,
        dictating: true
    )
    #expect(!empty)
}

@Test func joinLeavesEmptySidesAndInsertsASingleSpace() {
    #expect(VoiceParser.join("", "hello") == "hello")
    #expect(VoiceParser.join("hello", "") == "hello")
    #expect(VoiceParser.join("hello", "world") == "hello world")
    #expect(VoiceParser.join("hello ", "world") == "hello world")
    #expect(VoiceParser.join("hello", " world") == "hello world")
}

@Test func draftWithoutWakeKeepsTheRecognizedText() {
    #expect(VoiceParser.draftText(from: "  just a note  ") == "just a note")
    #expect(VoiceParser.draftText(from: "axiom") == "")
}

@Test func leftoverSpeechAfterAFinishedStreamDoesNotSend() {
    let leftover = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .finished,
        dictating: false
    )
    #expect(!leftover)
}

@Test func finishedFollowUpWhileDictatingDoesSend() {
    let followUp = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .finished,
        dictating: true
    )
    #expect(followUp)
}

@Test func failedPhaseWhileDictatingDoesSend() {
    let afterFail = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .failed("The request timed out."),
        dictating: true
    )
    #expect(afterFail)
}

@Test func noAutoSendWhileWaitingOrStreaming() {
    let waiting = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .waiting,
        dictating: true
    )
    #expect(!waiting)
    let streaming = VoiceParser.shouldAutoSend(
        optionOn: true,
        draft: "hello",
        silentFor: VoiceParser.silenceBuffer,
        phase: .streaming,
        dictating: true
    )
    #expect(!streaming)
}

@Test func cooldownDropsASecondWakeWithinTheWindow() {
    let first = Date(timeIntervalSince1970: 100)
    let tooSoon = Date(timeIntervalSince1970: 100 + VoiceParser.cooldown - 0.01)
    let later = Date(timeIntervalSince1970: 100 + VoiceParser.cooldown)
    #expect(VoiceParser.cooldownBlocks(lastWake: first, now: tooSoon))
    #expect(!VoiceParser.cooldownBlocks(lastWake: first, now: later))
    #expect(!VoiceParser.cooldownBlocks(lastWake: nil, now: first))
}

@Test func emptyWakeHidesAfterFourSeconds() {
    let opened = Date(timeIntervalSince1970: 10)
    let tooSoon = Date(timeIntervalSince1970: 13.9)
    let ready = Date(timeIntervalSince1970: 14)
    #expect(
        !VoiceParser.shouldHideEmptyWake(
            openedFromWake: true,
            draft: "",
            openedAt: opened,
            now: tooSoon
        )
    )
    #expect(
        VoiceParser.shouldHideEmptyWake(
            openedFromWake: true,
            draft: "",
            openedAt: opened,
            now: ready
        )
    )
    #expect(
        !VoiceParser.shouldHideEmptyWake(
            openedFromWake: true,
            draft: "still here",
            openedAt: opened,
            now: ready
        )
    )
    #expect(
        !VoiceParser.shouldHideEmptyWake(
            openedFromWake: false,
            draft: "",
            openedAt: opened,
            now: ready
        )
    )
}

@Test func voiceStatusOpensTheMatchingPrivacyPane() {
    let mic = VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.micDenied)
    #expect(mic?.absoluteString.contains("Privacy_Microphone") == true)
    #expect(mic?.absoluteString.contains("PrivacySecurity.extension") == true)
    let speech = VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.speechDenied)
    #expect(speech?.absoluteString.contains("Privacy_SpeechRecognition") == true)
    #expect(VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.captureFailed) == nil)
    #expect(VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.missingModel) == nil)
    #expect(VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.unsupportedModel) == nil)
    #expect(VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.downloading) == nil)
    #expect(VoiceStatusCopy.systemSettingsURL(for: VoiceStatusCopy.adHocPermission) == nil)
}

@Test func togglingVoiceOptionsDoesNotClearEndpointFields() {
    let suite = "aihud.tests.voice-persist"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("https://api.openai.com/v1", forKey: ChatSettings.urlKey)
    defaults.set("gpt-4o", forKey: ChatSettings.modelKey)
    VoiceSettings.saveWakeOnAxiom(true, to: defaults)
    VoiceSettings.savePauseToSend(true, to: defaults)
    #expect(defaults.bool(forKey: VoiceSettings.wakeOnAxiomKey))
    #expect(defaults.bool(forKey: VoiceSettings.pauseToSendKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    VoiceSettings.saveWakeOnAxiom(false, to: defaults)
    VoiceSettings.savePauseToSend(false, to: defaults)
    #expect(!defaults.bool(forKey: VoiceSettings.wakeOnAxiomKey))
    #expect(!defaults.bool(forKey: VoiceSettings.pauseToSendKey))
    #expect(defaults.string(forKey: ChatSettings.urlKey) == "https://api.openai.com/v1")
    #expect(defaults.string(forKey: ChatSettings.modelKey) == "gpt-4o")
    defaults.removePersistentDomain(forName: suite)
}

@Test @MainActor func synthesizedAxiomSentenceFillsTheQuestion() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("axiom-hud-\(UUID().uuidString).aiff")
    defer { try? FileManager.default.removeItem(at: url) }
    let synth = NSSpeechSynthesizer()
    let started = synth.startSpeaking("axiom what is the total mass of the sun", to: url)
    #expect(started)
    let spokeUntil = Date().addingTimeInterval(15)
    while synth.isSpeaking && Date() < spokeUntil {
        try await Task.sleep(for: .milliseconds(50))
    }
    let capture = VoiceCapture()
    let box = SpeechBox()
    capture.onTranscript = { text, isFinal in
        box.note(text, isFinal: isFinal)
    }
    capture.onFailure = { message in
        box.fail(message)
    }
    capture.transcribe(file: url)
    let deadline = Date().addingTimeInterval(45)
    while box.finalText.isEmpty && box.failure == nil && Date() < deadline {
        try await Task.sleep(for: .milliseconds(200))
    }
    #expect(box.failure == nil)
    let draft = VoiceParser.draftText(from: box.finalText)
    #expect(draft.localizedCaseInsensitiveContains("total mass of the sun"))
}

private final class SpeechBox: @unchecked Sendable {
    var finalText = ""
    var failure: String?
    func note(_ text: String, isFinal: Bool) {
        if isFinal { finalText = text }
    }
    func fail(_ message: String) {
        failure = message
    }
}
