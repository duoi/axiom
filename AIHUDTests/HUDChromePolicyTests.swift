import SwiftUI
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

@Test func screenCaptureDropsEveryAxiomWindowSoTheCardStaysUp() {
    let own: pid_t = 4242
    let windows: [(id: CGWindowID, pid: pid_t?)] = [
        (10, own), (11, 99), (12, own), (13, nil),
    ]
    #expect(ScreenGrab.excludedWindowIDs(windows, ownPID: own) == [10, 12])
}

@Test @MainActor func measurementHostLeavesTheLivePromptEditor() {
    let store = EndpointStore.isolated()
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

@Test func splitFlagOffKeepsThe108Window() {
    #expect(HUDSplitChromeLayout.panelHeight(splitEnabled: false, settledCapsuleHeight: 108, hasLip: false) == 108)
    #expect(
        HUDSplitChromeLayout.panelHeight(splitEnabled: false, settledCapsuleHeight: 108, hasLip: true)
            == 108 + HUDLayout.lipVisible
    )
    #expect(HUDSplitChromeLayout.panelHeight(splitEnabled: false, settledCapsuleHeight: 52, hasLip: false) == 108)
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: false,
        settledCapsuleHeight: 108,
        panelHeight: 108,
        showLip: false,
        cardWidth: 560,
        leadingWidths: [40],
        trailingWidths: [40]
    )
    #expect(frames.pills.isEmpty)
    #expect(frames.placement.plate.height == 108)
    #expect(HUDSplitChromeLayout.pointHitsChrome(CGPoint(x: 20, y: 54), frames: frames, splitEnabled: false))
}

@Test func splitIdleStacksTheCapsuleGapAndPills() {
    let capsule: CGFloat = 52
    let height = HUDSplitChromeLayout.panelHeight(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        hasLip: false
    )
    #expect(height == capsule + HUDSplitChromeLayout.pillGap + HUDSplitChromeLayout.pillHeight)
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        panelHeight: height,
        showLip: false,
        cardWidth: 560,
        leadingWidths: [80, 90],
        trailingWidths: [44, 40, 40]
    )
    #expect(frames.placement.plate.height == capsule)
    #expect(frames.placement.plate.maxY == height)
    #expect(frames.placement.revealed == 0)
    #expect(frames.pills.count == 5)
    let rowMax = frames.placement.plate.minY - HUDSplitChromeLayout.pillGap
    for pill in frames.pills {
        #expect(pill.maxY == rowMax)
        #expect(pill.height == HUDSplitChromeLayout.pillHeight)
    }
    #expect(frames.pills[0].minX == 0)
    #expect(frames.pills[1].minX == 80 + HUDSplitChromeLayout.pillSpacing)
    #expect(frames.pills[4].maxX == 560)
    #expect(frames.pills[2].minX > frames.pills[1].maxX + 1)
}

@Test func splitLipPushesPillsDownByTheRevealedAmount() {
    let capsule: CGFloat = 52
    let idle = HUDSplitChromeLayout.panelHeight(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        hasLip: false
    )
    let mid = idle + HUDLayout.lipVisible / 2
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        panelHeight: mid,
        showLip: true,
        cardWidth: 560,
        leadingWidths: [60],
        trailingWidths: [40]
    )
    #expect(frames.placement.plate.height == capsule)
    #expect(frames.placement.plate.maxY == mid)
    #expect(abs(frames.placement.revealed - HUDLayout.lipVisible / 2) < 0.01)
    #expect(abs(frames.placement.lip.maxY - frames.placement.plate.minY) < 0.01)
    #expect(frames.pills[0].maxY == frames.placement.plate.minY - frames.placement.revealed - HUDSplitChromeLayout.pillGap)
    #expect(frames.pills[1].maxY == frames.pills[0].maxY)
}

@Test func splitHolesMissAndChromeHits() {
    let capsule: CGFloat = 52
    let height = HUDSplitChromeLayout.panelHeight(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        hasLip: false
    )
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: true,
        settledCapsuleHeight: capsule,
        panelHeight: height,
        showLip: false,
        cardWidth: 560,
        leadingWidths: [80, 70],
        trailingWidths: [40]
    )
    let plate = frames.placement.plate
    #expect(HUDSplitChromeLayout.pointHitsChrome(CGPoint(x: plate.midX, y: plate.midY), frames: frames, splitEnabled: true))
    let gap = CGPoint(x: plate.midX, y: plate.minY - HUDSplitChromeLayout.pillGap / 2)
    #expect(!HUDSplitChromeLayout.pointHitsChrome(gap, frames: frames, splitEnabled: true))
    let left = frames.pills[1]
    let right = frames.pills[2]
    let between = CGPoint(x: (left.maxX + right.minX) / 2, y: left.midY)
    #expect(right.minX > left.maxX + 1)
    #expect(!HUDSplitChromeLayout.pointHitsChrome(between, frames: frames, splitEnabled: true))
    #expect(HUDSplitChromeLayout.pointHitsChrome(CGPoint(x: left.midX, y: left.midY), frames: frames, splitEnabled: true))
}

@Test func splitCapsuleCornerIsAPillUntilTheRowGrows() {
    let pill = HUDMetrics.rowHeight / 2
    #expect(HUDSplitChromeLayout.capsuleCornerRadius(height: HUDMetrics.rowHeight) == pill)
    let line = PromptLayout.lineHeight(for: PromptLayout.font())
    let mid = HUDSplitChromeLayout.capsuleCornerRadius(height: HUDMetrics.rowHeight + line / 2)
    #expect(mid < pill)
    #expect(mid > HUDMetrics.cornerRadius)
    #expect(HUDSplitChromeLayout.capsuleCornerRadius(height: 140) == HUDMetrics.cornerRadius)
}

@Test func frameMotionScalarUsesTheSameEase() {
    #expect(HUDFrameMotion.scalar(from: 52, to: 200, linearProgress: 0) == 52)
    #expect(HUDFrameMotion.scalar(from: 52, to: 200, linearProgress: 1) == 200)
    let mid = HUDFrameMotion.scalar(from: 52, to: 200, linearProgress: 0.5)
    #expect(abs(mid - 126) < 0.01)
}

@Test func pourSpringStartsAtZeroAndPeaksAboveOne() {
    #expect(HUDFrameMotion.pourSpring(elapsed: 0) == 0)
    #expect(HUDFrameMotion.pourSpring(elapsed: 0.35) > 1)
    #expect(HUDFrameMotion.pourDelay(rank: 0) == 0)
    #expect(HUDFrameMotion.pourDelay(rank: 5) == HUDFrameMotion.pourStagger * 2)
    #expect(HUDFrameMotion.pourPresentation(elapsed: 0, delay: 0.032, opening: true) == 0)
    #expect(HUDFrameMotion.pourPresentation(elapsed: 0, delay: 0.032, opening: false) == 1)
}

@Test func pourSpacingOpensTheGapWithoutLeavingNeighborsFused() {
    #expect(HUDFrameMotion.pourSpacing(slowestVerticalGap: -HUDFrameMotion.pourOverlap) == HUDFrameMotion.pourBridge)
    #expect(HUDFrameMotion.pourSpacing(slowestVerticalGap: HUDSplitChromeLayout.pillGap) == 0)
    let midway = HUDFrameMotion.pourSpacing(slowestVerticalGap: 8)
    #expect(midway < HUDSplitChromeLayout.pillSpacing)
    #expect(midway > 0)
}

@Test func tuckedPillOverlapsTheCapsuleAndPresentationOneSeatsIt() {
    let plate = CGRect(x: 0, y: 56, width: 560, height: 52)
    let rest = CGRect(x: 0, y: 0, width: 80, height: HUDSplitChromeLayout.pillHeight)
    let tuck = HUDFrameMotion.tuckedPillFrame(rest: rest, plate: plate, cardWidth: 560)
    #expect(abs((tuck.maxY - plate.minY) - HUDFrameMotion.pourOverlap) < 0.01)
    #expect(tuck.midX > rest.midX)
    let seated = HUDFrameMotion.pouredPillFrame(from: tuck, to: rest, presentation: 1)
    #expect(abs(seated.maxY - (plate.minY - HUDSplitChromeLayout.pillGap)) < 0.5)
    let neighbor = CGRect(x: 88, y: 0, width: 70, height: HUDSplitChromeLayout.pillHeight)
    #expect(neighbor.minX - rest.maxX == HUDSplitChromeLayout.pillSpacing)
}

@Test func chipAndLipOpacityFollowTheDisplayedHeight() {
    let prompt = HUDSplitChromeLayout.promptBlock(extraLines: 0)
    #expect(HUDSplitChromeLayout.chipOpacity(displayedCapsule: prompt, promptBlock: prompt) == 0)
    let full = prompt + HUDSplitChromeLayout.chipBand
    #expect(HUDSplitChromeLayout.chipOpacity(displayedCapsule: full, promptBlock: prompt) == 1)
    #expect(HUDSplitChromeLayout.lipCopyOpacity(revealed: 0) == 0)
    #expect(HUDSplitChromeLayout.lipCopyOpacity(revealed: HUDLayout.lipVisible / 2) == 0.5)
    #expect(HUDSplitChromeLayout.lipCopyOpacity(revealed: HUDLayout.lipVisible) == 1)
}

@Test func splitPillsTrackTheLiveCapsule() {
    let from = HUDMetrics.rowHeight
    let to: CGFloat = 200
    let midCapsule = HUDFrameMotion.scalar(from: from, to: to, linearProgress: 0.5)
    let fromPanel = HUDSplitChromeLayout.panelHeight(
        splitEnabled: true,
        settledCapsuleHeight: from,
        hasLip: false
    )
    let toPanel = HUDSplitChromeLayout.panelHeight(
        splitEnabled: true,
        settledCapsuleHeight: to,
        hasLip: false
    )
    let midPanel = HUDFrameMotion.scalar(from: fromPanel, to: toPanel, linearProgress: 0.5)
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: true,
        settledCapsuleHeight: midCapsule,
        panelHeight: midPanel,
        showLip: false,
        cardWidth: 560,
        leadingWidths: [80],
        trailingWidths: [40]
    )
    let plate = frames.placement.plate
    #expect(abs(plate.height - midCapsule) < 0.5)
    #expect(abs(frames.pills[0].maxY - (plate.minY - HUDSplitChromeLayout.pillGap)) < 0.5)
}

@MainActor
private func promptReachable(_ hud: HUDController) async -> (focused: Bool, clickable: Bool, detail: String) {
    hud.show()
    // Suspend instead of spinning the run loop, so the main-queue focus hop in show() can run.
    try? await Task.sleep(for: .milliseconds(600))
    hud.panel.contentView?.layoutSubtreeIfNeeded()
    guard let focus = hud.model.promptEditor?.promptFocusView else {
        return (false, false, "no prompt editor")
    }
    let responder = hud.panel.firstResponder
    var focused = false
    if let view = responder as? NSView {
        focused = view === focus || view.isDescendant(of: focus)
    }
    let center = focus.convert(NSPoint(x: focus.bounds.midX, y: focus.bounds.midY), to: nil)
    let hit = (hud.panel.contentView?.superview ?? hud.panel.contentView)?.hitTest(center)
    let clickable = hit.map { $0 === focus || $0.isDescendant(of: focus) } ?? false
    let detail = "responder=\(String(describing: responder.map { type(of: $0) })) "
        + "inPanel=\(focus.window === hud.panel) hit=\(String(describing: hit.map { type(of: $0) }))"
    return (focused, clickable, detail)
}

@Test @MainActor func newUIKeepsThePromptTypableAndSurvivesTurningItOff() async {
    let store = EndpointStore.isolated()
    let saved = store.usesNewUI
    defer { store.usesNewUI = saved }
    store.usesNewUI = true
    let hud = HUDController(store: store)
    defer { hud.panel.orderOut(nil) }

    let split = await promptReachable(hud)
    #expect(split.focused, "New UI focus: \(split.detail)")
    #expect(split.clickable, "New UI click: \(split.detail)")

    hud.panel.orderOut(nil)
    store.usesNewUI = false
    let classic = await promptReachable(hud)
    #expect(classic.focused, "Classic after New UI focus: \(classic.detail)")
    #expect(classic.clickable, "Classic after New UI click: \(classic.detail)")

    hud.panel.orderOut(nil)
    store.usesNewUI = true
    let again = await promptReachable(hud)
    #expect(again.focused, "New UI after classic focus: \(again.detail)")
    #expect(again.clickable, "New UI after classic click: \(again.detail)")
}


@Test func dismissTucksWithoutBouncingBeforeTheFadeEnds() {
    let fadeEnd = HUDFrameMotion.pourDismissFadeDelay + HUDPanelFade.duration
    for rank in 0...2 {
        let delay = HUDFrameMotion.pourDelay(rank: rank)
        var previous: CGFloat = 1
        for step in 0...100 {
            let t = fadeEnd * Double(step) / 100
            let value = HUDFrameMotion.pourPresentation(elapsed: t, delay: delay, opening: false)
            #expect(value >= 0 && value <= 1, "rank \(rank) t \(t): \(value)")
            #expect(value <= previous + 0.0001, "rank \(rank) t \(t) moved back out")
            previous = value
        }
        #expect(HUDFrameMotion.pourPresentation(elapsed: fadeEnd, delay: delay, opening: false) == 0)
    }
}

@Test @MainActor func agentRowLeavesWallpaperBetweenTheColumns() {
    let store = EndpointStore.isolated()
    let model = HUDModel(store: store)
    func width(_ id: HUDPillID) -> CGFloat {
        let host = ClickThroughHosting(rootView: HUDView(model: model, store: store, region: .pill(id)))
        host.layoutSubtreeIfNeeded()
        return max(HUDSplitChromeLayout.pillHeight, ceil(host.fittingSize.width))
    }
    let columns = HUDPillID.columns(showsPreset: true)
    #expect(columns.leading.contains(.contextIcon))
    #expect(!HUDPillID.columns(showsPreset: false).leading.contains(.contextIcon))
    let frames = HUDSplitChromeLayout.frames(
        splitEnabled: true,
        settledCapsuleHeight: HUDMetrics.rowHeight,
        panelHeight: HUDMetrics.minCardHeight,
        showLip: false,
        cardWidth: HUDMetrics.cardWidth,
        leadingWidths: columns.leading.map(width),
        trailingWidths: columns.trailing.map(width)
    )
    let lastLeading = frames.pills[columns.leading.count - 1]
    let firstTrailing = frames.pills[columns.leading.count]
    #expect(firstTrailing.minX - lastLeading.maxX >= HUDSplitChromeLayout.pillSpacing)
}

@Test @MainActor func pillHandsClicksStraightToItsContent() {
    let pill = PillGlassView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
    let inner = NSView(frame: pill.bounds)
    pill.contentView = inner
    pill.layoutSubtreeIfNeeded()
    let hit = pill.hitTest(NSPoint(x: 60, y: 20))
    #expect(hit === inner || hit?.isDescendant(of: inner) == true)
}

@MainActor
private func clickToggles(_ hud: HUDController, at view: NSView, x: CGFloat) async throws -> Bool {
    let before = hud.model.captureArmed
    try await click(hud, at: view, x: x)
    return hud.model.captureArmed != before
}

@MainActor
private func click(_ hud: HUDController, at view: NSView, x: CGFloat) async throws {
    let point = view.convert(NSPoint(x: x, y: view.bounds.midY), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hud.panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
        ))
        NSApp.sendEvent(event)
        try? await Task.sleep(for: .milliseconds(100))
    }
    try? await Task.sleep(for: .milliseconds(300))
}

@Test @MainActor func newUIPillClickRunsItsAction() async throws {
    let store = EndpointStore.isolated()
    let saved = store.usesNewUI
    defer { store.usesNewUI = saved }
    store.usesNewUI = true
    let hud = HUDController(store: store)
    defer { hud.panel.orderOut(nil) }
    hud.show()
    try? await Task.sleep(for: .milliseconds(900))
    // Look pills up by id: with Reduce Transparency (as on CI runners) they are solid views, not glass.
    let capture = try #require(hud.pillViews[.capture])
    if let agent = hud.pillViews[.preset] {
        let preset = hud.model.session.preset
        try await click(hud, at: agent, x: 30)
        #expect(hud.model.session.preset != preset, "Agent pill click")
    }
    #expect(try await clickToggles(hud, at: capture, x: 30))
}


@Test func splitMarginHoldsTheOpeningOvershoot() {
    let peak = (1...700).map { HUDFrameMotion.pourSpring(elapsed: Double($0) / 1000) }.max() ?? 1
    let margin = HUDSplitChromeLayout.windowMargin
    let card = HUDMetrics.cardWidth
    let plate = CGRect(x: 0, y: HUDSplitChromeLayout.pillGap + HUDSplitChromeLayout.pillHeight, width: card, height: HUDMetrics.rowHeight)
    let edges = [
        CGRect(x: 0, y: 0, width: HUDSplitChromeLayout.pillHeight, height: HUDSplitChromeLayout.pillHeight),
        CGRect(x: card - HUDSplitChromeLayout.pillHeight, y: 0, width: HUDSplitChromeLayout.pillHeight, height: HUDSplitChromeLayout.pillHeight),
    ]
    for rest in edges {
        let tuck = HUDFrameMotion.tuckedPillFrame(rest: rest, plate: plate, cardWidth: card)
        let swung = HUDFrameMotion.pouredPillFrame(from: tuck, to: rest, presentation: peak)
        #expect(swung.minX >= -margin.left)
        #expect(swung.maxX <= card + margin.right)
        #expect(swung.minY >= -margin.bottom)
    }
}

@Test @MainActor func chromeMarginGrowsTheWindowAroundTheCard() {
    let panel = HUDPanel()
    let card = NSRect(x: 300, y: 400, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
    panel.setFrame(card, display: false)
    let margin = HUDSplitChromeLayout.windowMargin
    panel.chromeMargin = margin
    #expect(panel.cardFrame == card)
    #expect(panel.frame == NSRect(
        x: card.minX - margin.left,
        y: card.minY - margin.bottom,
        width: card.width + margin.left + margin.right,
        height: card.height + margin.top + margin.bottom
    ))
    panel.chromeMargin = NSEdgeInsetsZero
    #expect(panel.frame == card)
}

@Test @MainActor func reopeningDuringTheNewUIFadePoursThePillsBackOut() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    let store = EndpointStore.isolated()
    store.usesNewUI = true
    let hud = HUDController(store: store)
    defer { hud.panel.orderOut(nil) }
    hud.show()
    hud.userDismiss(clickOutside: false)
    #expect(hud.panel.isFadingOut)
    #expect(hud.chrome?.pourOpening == false)

    hud.show()
    #expect(hud.chrome?.pourOpening == true)
}



@Test func settingsRisesAboveTheCardOnlyWhileYouUseIt() {
    let card = NSWindow.Level.floating
    #expect(AuxiliaryWindowLevel.level(appActive: true, isKey: true, ownsFocus: false, cardLevel: card) == card)
    // Its editor sheet or Add Provider popover has focus: still in use.
    #expect(AuxiliaryWindowLevel.level(appActive: true, isKey: false, ownsFocus: true, cardLevel: card) == card)
    // You went back to the card.
    #expect(AuxiliaryWindowLevel.level(appActive: true, isKey: false, ownsFocus: false, cardLevel: card) == .normal)
    // Another app is in front, or Axiom never became active: other apps must be able to cover it.
    #expect(AuxiliaryWindowLevel.level(appActive: false, isKey: true, ownsFocus: false, cardLevel: card) == .normal)
    #expect(AuxiliaryWindowLevel.level(appActive: false, isKey: true, ownsFocus: true, cardLevel: card) == .normal)
}

@Test @MainActor func focusingAPromptWithTextPutsTheCaretAtTheEnd() {
    // AppKit selects a field's whole text when it takes focus, so the next key would replace a restored draft.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    let field = ClickThroughTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 40))
    window.contentView?.addSubview(field)
    field.stringValue = "What is the total mass of the sun?"
    #expect(window.makeFirstResponder(field))
    let selection = field.currentEditor()?.selectedRange
    #expect(selection?.length == 0)
    #expect(selection?.location == (field.stringValue as NSString).length)
}

@Test @MainActor func fillingTheFocusedPromptLeavesNothingSelected() {
    // Dictation and the demo prompt fill the field while it has focus; the text must not end up selected.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    let field = ClickThroughTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 40))
    window.contentView?.addSubview(field)
    #expect(window.makeFirstResponder(field))
    field.applyPrompt("Write a haiku")
    field.applyPrompt("Write a haiku about coffee")
    let selection = field.currentEditor()?.selectedRange
    #expect(selection?.length == 0)
    #expect(selection?.location == ("Write a haiku about coffee" as NSString).length)
}

@Test @MainActor func refreshingThePromptKeepsTheCaretWhereYouPutIt() {
    // SwiftUI pushes the same text back on every update; that must not move the caret you placed mid-text.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    let field = ClickThroughTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 40))
    window.contentView?.addSubview(field)
    field.applyPrompt("What is the mass of the sun?")
    #expect(window.makeFirstResponder(field))
    field.currentEditor()?.selectedRange = NSRange(location: 8, length: 0)
    field.applyPrompt("What is the mass of the sun?")
    #expect(field.currentEditor()?.selectedRange == NSRange(location: 8, length: 0))
}
