import AppKit
import Foundation
import Testing
@testable import Axiom
@Test func frameMotionDurationMatchesThePanelFade() {
    #expect(HUDFrameMotion.duration(reduceMotion: false) == HUDPanelFade.duration)
    #expect(HUDFrameMotion.duration(reduceMotion: false) == HUDLayout.scrollerFadeDuration)
    #expect(HUDFrameMotion.duration(reduceMotion: false) == 0.16)
    #expect(HUDFrameMotion.duration(reduceMotion: true) == 0)
}

@Test func frameMotionKeepsThePinnedEdge() {
    let tall = NSRect(x: 40, y: 100, width: 560, height: 400)
    let compact = NSRect(x: 40, y: 392, width: 560, height: 108)
    #expect(tall.maxY == compact.maxY)
    #expect(HUDFrameMotion.pinsTop(from: tall, to: compact))
    let mid = HUDFrameMotion.frame(from: tall, to: compact, linearProgress: 0.5)
    #expect(abs(mid.maxY - tall.maxY) < 0.01)
    #expect(mid.height < tall.height)
    #expect(mid.height > compact.height)
    #expect(HUDFrameMotion.frame(from: tall, to: compact, linearProgress: 0) == tall)
    #expect(HUDFrameMotion.frame(from: tall, to: compact, linearProgress: 1) == compact)

    let taller = NSRect(x: 40, y: 100, width: 560, height: 520)
    #expect(tall.minY == taller.minY)
    #expect(!HUDFrameMotion.pinsTop(from: tall, to: taller))
    let up = HUDFrameMotion.frame(from: tall, to: taller, linearProgress: 0.5)
    #expect(abs(up.minY - tall.minY) < 0.01)
    #expect(up.maxY > tall.maxY)
    #expect(up.height < taller.height)
}

@Test func topPinnedCollapseHoldsTheTopAtMidpoint() {
    let tall = NSRect(x: 40, y: 100, width: 560, height: 400)
    let compact = NSRect(x: 40, y: 392.6, width: 560, height: 108)
    #expect(tall.maxY == 500)
    #expect(abs(tall.maxY - compact.maxY) <= 1)
    #expect(HUDFrameMotion.pinsTop(from: tall, to: compact))
    let mid = HUDFrameMotion.frame(from: tall, to: compact, linearProgress: 0.5)
    #expect(mid.maxY == tall.maxY)
    #expect(mid.height < tall.height)
    #expect(mid.height > compact.height)
    let host = HUDFrameMotion.promptHostFrame(
        plateWidth: 560,
        plateHeight: tall.height,
        contentHeight: compact.height
    )
    #expect(host.height == compact.height)
    #expect(host.maxY == tall.height)
    #expect(host.minY == tall.height - compact.height)
}

@Test func promptHostStaysOnThePlateTopWhileTheWindowIsShorter() {
    let growing = HUDFrameMotion.promptHostFrame(plateWidth: 560, plateHeight: 180, contentHeight: 388)
    #expect(growing.height == 388)
    #expect(growing.maxY == 180)
    #expect(growing.minY == CGFloat(180) - 388)
}

@Test func raisedTopContractionMayMoveTheTop() {
    let raised = NSRect(x: 40, y: 80, width: 560, height: 520)
    let compact = NSRect(x: 40, y: 392, width: 560, height: 108)
    #expect(raised.maxY == 600)
    #expect(compact.maxY == 500)
    #expect(abs(raised.maxY - compact.maxY) > 1)
    #expect(!HUDFrameMotion.pinsTop(from: raised, to: compact))
    let mid = HUDFrameMotion.frame(from: raised, to: compact, linearProgress: 0.5)
    #expect(mid.maxY < raised.maxY)
    #expect(mid.maxY > compact.maxY)
}

@Test func windowCaptureLeavesThePanelUp() {
    #expect(!CapturePanelConceal.hidesPanel(target: .window))
    #expect(CapturePanelConceal.hidesPanel(target: .screen))
}

@Test @MainActor func measurementHostLeavesTheLivePromptEditor() {
    let store = EndpointStore()
    let model = HUDModel(store: store)
    let live = ClickThroughHosting(rootView: HUDView(model: model, store: store))
    live.setFrameSize(NSSize(width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight))
    live.layoutSubtreeIfNeeded()
    let editor = model.promptEditor
    #expect(editor != nil)
    model.promptLineCount = 99
    let probe = ClickThroughHosting(
        rootView: HUDView(model: model, store: store, measuresOnly: true)
    )
    probe.setFrameSize(HUDLayout.hostingFitSize)
    probe.layoutSubtreeIfNeeded()
    #expect(model.promptEditor === editor)
    #expect(model.promptLineCount == 99)
}

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

@Test func inFlightShimmerPickerListsMonochromeStyle() {
    #expect(InFlightShimmerStyle.default == .whiteSweep)
    #expect(InFlightShimmerStyle.allCases.map(\.title) == [
        "White sweep",
    ])
    #expect(InFlightShimmerStyle.resolved(nil) == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("nope") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("chatgpt") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("grok") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("iridescent-mesh") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("ocean-mesh") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("wide-hue-slide") == .whiteSweep)
    #expect(InFlightShimmerStyle.resolved("white-sweep") == .whiteSweep)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-white-sweep") == .whiteSweep)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-iridescent-mesh") == nil)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-chatgpt") == nil)
    #expect(InFlightShimmerStyle.fromDebugCommand("shimmer-grok") == nil)
    #expect(InFlightShimmerStyle.fromDebugCommand("waiting") == nil)
    #expect(InFlightShimmerStyle.whiteSweep.debugCommand == "shimmer-white-sweep")
}

@Test @MainActor func inFlightShimmerUsesThePromptEditorsGlyphMetrics() {
    let font = PromptLayout.font()
    #expect(font.pointSize == PromptLayout.fontSize)
    let bounds = NSRect(x: 0, y: 0, width: 420, height: HUDMetrics.rowHeight)
    let plain = NSTextFieldCell(textCell: "What is the total mass of the sun?")
    plain.font = font
    plain.isBordered = false
    plain.isBezeled = false
    plain.drawsBackground = false
    plain.usesSingleLineMode = true
    plain.lineBreakMode = .byClipping
    let base = plain.drawingRect(forBounds: bounds)
    let expected = PromptLayout.singleLineGlyphRect(cellRect: base, font: font)
    let cell = CenteredPromptCell(textCell: "What is the total mass of the sun?")
    cell.font = font
    cell.isBordered = false
    cell.isBezeled = false
    cell.drawsBackground = false
    cell.usesSingleLineMode = true
    cell.lineBreakMode = .byClipping
    #expect(cell.drawingRect(forBounds: bounds) == expected)
    #expect(cell.titleRect(forBounds: bounds) == expected)

    let host = PromptHostView(frame: bounds)
    host.showsInFlightShimmer = true
    #expect(host.field.font == font)
    #expect(host.textView.font == font)
    #expect(host.field.showsInFlightShimmer)
    #expect(host.textView.showsInFlightShimmer)
    #expect(host.textView.textContainerInset == PromptLayout.multilineTextContainerInset)
    #expect(host.textView.textContainer?.lineFragmentPadding == PromptLayout.multilineFragmentPadding)
    let line = PromptLayout.lineHeight(for: font)
    #expect(host.textView.defaultParagraphStyle?.minimumLineHeight == line)
    #expect(host.textView.defaultParagraphStyle?.maximumLineHeight == line)
    host.isMultiline = true
    host.frame = NSRect(
        x: 0,
        y: 0,
        width: 420,
        height: PromptLayout.rowHeight(visibleLines: 2, font: font)
    )
    host.layoutSubtreeIfNeeded()
    #expect(abs(host.scroll.frame.minY - PromptLayout.verticalInset(font: font)) < 0.5)
}

@Test func inFlightShimmerBandLoopsWithoutResting() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    #expect(InFlightPromptShimmer.bandPhase(at: start, duration: 1.8) == 0)
    let mid = Date(timeIntervalSinceReferenceDate: 0.9)
    #expect(abs(InFlightPromptShimmer.bandPhase(at: mid, duration: 1.8) - 0.5) < 0.001)
    let wrapped = Date(timeIntervalSinceReferenceDate: 1.8)
    #expect(InFlightPromptShimmer.bandPhase(at: wrapped, duration: 1.8) == 0)
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

@Test func controlShortcutsApplyOnlyWhileTheCardIsKey() {
    func act(
        keyCode: UInt16,
        control: Bool = false,
        command: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        panelIsKey: Bool = true,
        menuTracking: Bool = false,
        hasAttachedSheet: Bool = false,
        isComposing: Bool = false,
        bindings: [HUDShortcut: [BoundShortcut]] = HUDShortcuts.defaults
    ) -> HUDShortcut? {
        HUDShortcuts.action(
            keyCode: keyCode,
            control: control,
            command: command,
            option: option,
            shift: shift,
            panelIsKey: panelIsKey,
            menuTracking: menuTracking,
            hasAttachedSheet: hasAttachedSheet,
            isComposing: isComposing,
            bindings: bindings
        )
    }

    #expect(act(keyCode: 0, control: true) == .cyclePreset)
    #expect(act(keyCode: 1, control: true) == .cycleCapture)
    #expect(act(keyCode: 8, control: true) == .addContext)
    #expect(act(keyCode: 15, control: true) == .toggleIncognito)
    #expect(act(keyCode: 39, control: true) == .toggleDictation)
    #expect(act(keyCode: 53) == .hide)
    #expect(act(keyCode: 36) == .send)
    #expect(act(keyCode: 36, option: true) == .newline)
    #expect(act(keyCode: 36, shift: true) == .newline)
    #expect(act(keyCode: 76) == .send)
    #expect(act(keyCode: 0, command: true) == nil)
    #expect(act(keyCode: 0, control: true, command: true) == nil)
    #expect(act(keyCode: 0, control: true, option: true) == nil)
    #expect(act(keyCode: 0, control: true, shift: true) == nil)
    #expect(act(keyCode: 0, control: true, panelIsKey: false) == nil)
    #expect(act(keyCode: 0, control: true, menuTracking: true) == nil)
    #expect(act(keyCode: 0, control: true, hasAttachedSheet: true) == nil)
    #expect(act(keyCode: 36, isComposing: true) == nil)
    #expect(act(keyCode: 0, control: true, isComposing: true) == nil)
    let recording = BoundShortcut(keyCode: 15, control: true, command: false, option: false, shift: false)
    #expect(HUDShortcuts.defaults[.toggleIncognito] == [recording])
    #expect(act(keyCode: 15, control: true, bindings: [.toggleIncognito: [recording]]) == .toggleIncognito)
    #expect(act(keyCode: 0, control: true, bindings: [.toggleIncognito: [recording]]) == nil)
}

@Test func controlSCyclesCaptureOnThenTheOtherTargetThenOff() {
    let enabled = HUDCaptureCycle.advance(armed: false, target: .screen, toggledOption: false)
    #expect(enabled.armed)
    #expect(enabled.target == .screen)
    #expect(!enabled.toggledOption)

    let flipped = HUDCaptureCycle.advance(
        armed: enabled.armed,
        target: enabled.target,
        toggledOption: enabled.toggledOption
    )
    #expect(flipped.armed)
    #expect(flipped.target == .window)
    #expect(flipped.toggledOption)

    let off = HUDCaptureCycle.advance(
        armed: flipped.armed,
        target: flipped.target,
        toggledOption: flipped.toggledOption
    )
    #expect(!off.armed)
    #expect(off.target == .window)
    #expect(!off.toggledOption)

    let armedAgain = HUDCaptureCycle.advance(armed: false, target: .window, toggledOption: true)
    #expect(armedAgain.armed)
    #expect(armedAgain.target == .window)
    #expect(!armedAgain.toggledOption)

    let backToScreen = HUDCaptureCycle.advance(
        armed: true,
        target: .window,
        toggledOption: false
    )
    #expect(backToScreen.armed)
    #expect(backToScreen.target == .screen)
}
