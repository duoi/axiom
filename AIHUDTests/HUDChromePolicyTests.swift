import Foundation
import Testing
@testable import Axiom
@Test func composingOrbShowsOnlyWhileWaitingWithEmptyAnswer() {
    #expect(ReplyWaitingChrome.showsComposingOrb(phase: .waiting, answer: ""))
    #expect(ReplyWaitingChrome.showsComposingOrb(phase: .streaming, answer: ""))
    #expect(!ReplyWaitingChrome.showsComposingOrb(phase: .waiting, answer: "hi"))
    #expect(!ReplyWaitingChrome.showsComposingOrb(phase: .streaming, answer: "hi"))
    #expect(!ReplyWaitingChrome.showsComposingOrb(phase: .finished, answer: ""))
}

@Test func historyChromeHidesChevronWhileWaitingWithoutReply() {
    #expect(
        !HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .composing,
            historyExpanded: false
        )
    )
    #expect(
        !HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .waiting,
            historyExpanded: false
        )
    )
    #expect(
        !HistoryChromePolicy.showsExpandChevron(
            answer: "",
            phase: .waiting,
            historyExpanded: false,
            hasUserTurns: true
        )
    )
    #expect(
        HistoryChromePolicy.showsReplyRegion(
            answer: "Hello",
            phase: .finished,
            historyExpanded: false
        )
    )
    #expect(
        HistoryChromePolicy.showsExpandChevron(
            answer: "Hello",
            phase: .finished,
            historyExpanded: false,
            hasUserTurns: true
        )
    )
    #expect(
        HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .failed("nope"),
            historyExpanded: false
        )
    )
    #expect(
        HistoryChromePolicy.showsExpandChevron(
            answer: "",
            phase: .failed("nope"),
            historyExpanded: false,
            hasUserTurns: true
        )
    )
    #expect(
        HistoryChromePolicy.showsReplyRegion(
            answer: "",
            phase: .waiting,
            historyExpanded: true
        )
    )
    #expect(
        HistoryChromePolicy.showsExpandChevron(
            answer: "",
            phase: .waiting,
            historyExpanded: true,
            hasUserTurns: true
        )
    )
    #expect(
        !HistoryChromePolicy.showsExpandChevron(
            answer: "Hello",
            phase: .finished,
            historyExpanded: false,
            hasUserTurns: false
        )
    )
}

@Test func glowOrbChoicesAreNamedDistinctly() {
    #expect(ThinkingOrbChoice.composingGlow.title == "Composing glow")
    #expect(ThinkingOrbChoice.workingGlow.usesGlow)
    #expect(!ThinkingOrbChoice.composing.usesGlow)
    #expect(ThinkingOrbChoice.pulsingOrb.title == "Pulsing orb")
    #expect(ThinkingOrbChoice.pulsingOrb.usesPulsingOrb)
    #expect(ThinkingOrbChoice.production == .composing)
    #expect(ThinkingOrbChoice.allCases.count == 19)
}

@Test func inFlightShimmerPickerListsEveryDemoTextStyle() {
    #expect(InFlightShimmerStyle.default == .chatGPTStyle)
    #expect(InFlightShimmerStyle.allCases.map(\.title) == [
        "ChatGPT style",
        "Grok style",
        "ShimmeringText",
        "Summerizing the text",
        "Processing label",
    ])
    #expect(InFlightShimmerStyle.resolved(nil) == .chatGPTStyle)
    #expect(InFlightShimmerStyle.resolved("") == .chatGPTStyle)
    #expect(InFlightShimmerStyle.resolved("nope") == .chatGPTStyle)
    #expect(InFlightShimmerStyle.resolved("grok") == .grokStyle)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-chatgpt") == .chatGPTStyle)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-summerizing-the-text") == .summerizingTheText)
    #expect(InFlightShimmerStyle.fromDebugCommand("waiting") == nil)
    #expect(InFlightShimmerStyle.chatGPTStyle.debugCommand == "shimmer-chatgpt")
}

@Test func inFlightShimmerPhaseRestartsAfterRepeatDelay() {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    #expect(InFlightPromptShimmer.phase(at: start, duration: 2, repeatDelay: 0.5) == 0)
    let mid = Date(timeIntervalSinceReferenceDate: 101)
    #expect(abs(InFlightPromptShimmer.phase(at: mid, duration: 2, repeatDelay: 0.5) - 0.5) < 0.001)
    let rest = Date(timeIntervalSinceReferenceDate: 102.2)
    #expect(InFlightPromptShimmer.phase(at: rest, duration: 2, repeatDelay: 0.5) == 0)
}

@Test func promptInFlightKeepsDraftUntilProcessed() {
    #expect(PromptInFlightPolicy.promptDraft(whileSending: "Hello") == "Hello")
    #expect(PromptInFlightPolicy.promptDraftAfterSuccess().isEmpty)
    #expect(PromptInFlightPolicy.promptDraftAfterFailure(submitted: "Hello") == "Hello")
    #expect(!PromptInFlightPolicy.isEditable(phase: .waiting))
    #expect(!PromptInFlightPolicy.isEditable(phase: .streaming))
    #expect(PromptInFlightPolicy.isEditable(phase: .finished))
    #expect(PromptInFlightPolicy.isEditable(phase: .failed("x")))
    #expect(PromptInFlightPolicy.isEditable(phase: .composing))
    #expect(!PromptInFlightPolicy.allowsDictation(phase: .waiting))

    var session = Session()
    session.draft = "Keep visible"
    _ = session.send()
    #expect(session.draft == "Keep visible")
    #expect(session.phase == .waiting)
    session.finish()
    #expect(session.draft.isEmpty)
    #expect(PromptInFlightPolicy.isEditable(phase: session.phase))

    session.draft = "Retry me"
    _ = session.send()
    session.fail("boom")
    #expect(session.draft == "Retry me")
    #expect(PromptInFlightPolicy.isEditable(phase: session.phase))
}
