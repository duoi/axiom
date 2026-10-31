import AppKit
import CoreGraphics

enum HUDMetrics {
    static let cardWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 24
    static let inset: CGFloat = 20
    static let controlSize: CGFloat = 24
    static let pillInset: CGFloat = 8
    static let rowHeight: CGFloat = 52
    static let controlSpacing: CGFloat = 20
    static let sidebarWidth: CGFloat = 200
    static let minCardHeight: CGFloat = 108
    static let settingsSize = CGSize(width: 680, height: 520)
    static let debugSize = CGSize(width: 440, height: 720)
    static let transcriptSize = CGSize(width: 640, height: 520)
}

enum HUDLayout {
    /// Visible peek below the plate. Extra window growth is this amount.
    static let lipVisible: CGFloat = 28
    /// The warning sits this far in from each side of the card, clear of the corner wings.
    static let lipInset: CGFloat = 24
    /// Bottom corners of the warning. Smaller than the plate so it reads as its own lip.
    static let lipCorner: CGFloat = 16
    static var lipHeight: CGFloat { lipVisible }
    /// Ignore sub-point and 1pt fittingSize flicker so the panel does not step.
    static let heightFlicker: CGFloat = 1
    /// Assistant reply grows this many wrapped lines downward, top edge pinned.
    static let replyDownLines = 15
    /// After the down cap, this many more lines grow upward, bottom edge pinned.
    static let replyUpLines = 15
    static var replyMaxLines: Int { replyDownLines + replyUpLines }
    /// SwiftUI `.font(.body)` on the compact reply. Same face used to count wraps.
    static var replyFont: NSFont { .preferredFont(forTextStyle: .body) }
    static let replyLineHeight: CGFloat = PromptLayout.lineHeight(for: replyFont)
    /// Compact answer and the shared reply/history scroll column use `HUDMetrics.inset` (20) on each side.
    static var replyTextWidth: CGFloat { rowWidth }

    static func cardHeight() -> CGFloat {
        HUDMetrics.minCardHeight
    }

    /// Width-locked, height-unbounded proposal so wrapped replies measure taller than the idle card.
    static var hostingFitSize: NSSize {
        NSSize(width: HUDMetrics.cardWidth, height: 10_000)
    }

    static func cardHeight(fittingHeight: CGFloat) -> CGFloat {
        max(cardHeight(), fittingHeight)
    }

    /// Idle leftover below the two 52pt rows. Keep it when a reply grows the card so the toolbar does not sit on the glass edge.
    static var cardBottomSlack: CGFloat {
        max(0, HUDMetrics.minCardHeight - HUDMetrics.rowHeight * 2)
    }

    /// Prompt and toolbar content width. `HUDMetrics.inset` (20) sits on each side of the 560pt card.
    static var rowWidth: CGFloat { HUDMetrics.cardWidth - 2 * HUDMetrics.inset }

    static func windowHeight(card: CGFloat, hasLip: Bool) -> CGFloat {
        max(HUDMetrics.minCardHeight, card) + (hasLip ? lipVisible : 0)
    }

    static func lipWidth(cardWidth: CGFloat) -> CGFloat {
        max(0, cardWidth - 2 * lipInset)
    }

    /// The warning only. It does not climb the plate corner.
    static func lipFrame(cardWidth: CGFloat) -> CGRect {
        CGRect(x: lipInset, y: 0, width: lipWidth(cardWidth: cardWidth), height: lipVisible)
    }

    struct LipPlacement: Equatable, Sendable {
        var plate: CGRect
        var lip: CGRect
        var revealed: CGFloat
    }

    /// Plate stays on the window top. `revealed` is only the gap the window has already opened,
    /// so the card does not jump up to reserve the lip before that gap exists.
    static func lipPlacement(
        windowHeight: CGFloat,
        cardHeight: CGFloat,
        cardWidth: CGFloat,
        hasLip: Bool,
        minimumCardHeight: CGFloat = HUDMetrics.minCardHeight
    ) -> LipPlacement {
        let card = max(minimumCardHeight, cardHeight)
        let revealed = hasLip ? min(lipVisible, max(0, windowHeight - card)) : 0
        let plateHeight = min(card, max(0, windowHeight - revealed))
        let plateY = hasLip ? max(0, windowHeight - plateHeight) : 0
        let lip = lipFrame(cardWidth: cardWidth).offsetBy(dx: 0, dy: revealed - lipVisible)
        return LipPlacement(
            plate: CGRect(x: 0, y: plateY, width: cardWidth, height: plateHeight),
            lip: lip,
            revealed: revealed
        )
    }

    /// Lets the warning show under the plate without clipping or reshaping the plate's continuous corner.
    static func applyLipWindowMask(to view: NSView, revealed: CGFloat) {
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        let peek = min(lipVisible, max(0, revealed))
        guard peek > 0.5, view.bounds.width > 1, view.bounds.height > 1 else {
            view.layer?.mask = nil
            return
        }
        view.layer?.cornerRadius = 0
        view.layer?.masksToBounds = false
        let mask = CALayer()
        mask.frame = view.bounds
        let cardHeight = view.bounds.height - peek
        let plate = CALayer()
        plate.frame = CGRect(
            x: view.bounds.minX,
            y: view.bounds.minY + peek,
            width: view.bounds.width,
            height: cardHeight
        )
        plate.backgroundColor = NSColor.white.cgColor
        plate.cornerRadius = HUDMetrics.cornerRadius
        plate.cornerCurve = .continuous
        plate.masksToBounds = true
        let band = CALayer()
        let lip = lipFrame(cardWidth: view.bounds.width)
        var bandFrame = lip.offsetBy(dx: view.bounds.minX, dy: view.bounds.minY)
        bandFrame.size.height = peek
        bandFrame.origin.y = view.bounds.minY
        band.frame = bandFrame
        band.backgroundColor = NSColor.white.cgColor
        band.cornerRadius = lipCorner
        band.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        band.masksToBounds = true
        mask.addSublayer(plate)
        mask.addSublayer(band)
        view.layer?.mask = mask
    }

    static func settledHeight(
        proposed: CGFloat,
        previous: CGFloat,
        lineCount: Int,
        multiline: Bool,
        minimum: CGFloat = HUDMetrics.minCardHeight
    ) -> CGFloat {
        let next = max(minimum, proposed)
        let prior = max(minimum, previous)
        let delta = next - prior
        if abs(delta) <= heightFlicker {
            return prior
        }
        // Streamed wraps grow a fraction of the prompt line. Take that growth.
        if delta > heightFlicker {
            return next
        }
        let line = PromptLayout.promptLineHeight
        if multiline {
            let extra = max(0, lineCount - 1)
            if extra == 0, abs(delta) < line {
                return prior
            }
            if abs(delta) + heightFlicker >= line {
                return next
            }
            return prior
        }
        if abs(delta) < line {
            return prior
        }
        return next
    }

    /// AppKit `origin.y` is the bottom. Keep it put and raise `maxY` by growing `height`.
    static func framePinnedBottom(current: NSRect, height: CGFloat) -> NSRect {
        let nextHeight = max(HUDMetrics.minCardHeight, height)
        var next = current
        next.size.width = HUDMetrics.cardWidth
        next.size.height = nextHeight
        return next
    }

    static func replyVisibleLines(_ lines: Int) -> Int {
        min(max(0, lines), replyMaxLines)
    }

    static func replyBodyHeight(lines: Int, lineHeight: CGFloat = replyLineHeight) -> CGFloat {
        CGFloat(replyVisibleLines(lines)) * lineHeight
    }

    static func replyExtraUpHeight(lines: Int, lineHeight: CGFloat = replyLineHeight) -> CGFloat {
        CGFloat(max(0, replyVisibleLines(lines) - replyDownLines)) * lineHeight
    }

    static func cardHeight(
        chromeHeight: CGFloat,
        replyLines: Int,
        lineHeight: CGFloat = replyLineHeight
    ) -> CGFloat {
        max(HUDMetrics.minCardHeight, chromeHeight + replyBodyHeight(lines: replyLines, lineHeight: lineHeight))
    }

    /// Reply/history vertical padding outside the line body (12pt each side).
    static let replyScrollVerticalPadding: CGFloat = 24

    /// Expanded history uses the full 30-line viewport for down/up framing.
    static func replyGrowthLines(answerLines: Int, historyExpanded: Bool) -> Int {
        if historyExpanded {
            return replyMaxLines
        }
        return max(0, answerLines)
    }

    /// Never size the card taller than chrome + 30 reply lines (scroll the rest).
    static func cappedCardHeight(
        proposed: CGFloat,
        chromeHeight: CGFloat,
        lineHeight: CGFloat = replyLineHeight
    ) -> CGFloat {
        let maxHeight = cardHeight(
            chromeHeight: chromeHeight,
            replyLines: replyMaxLines,
            lineHeight: lineHeight
        )
        return min(max(HUDMetrics.minCardHeight, proposed), maxHeight)
    }

    /// Keep the panel fully inside `visible`. Shrinks if taller/wider than the screen.
    static func clampFrame(_ frame: NSRect, to visible: NSRect) -> NSRect {
        guard visible.width > 0, visible.height > 0 else { return frame }
        var next = frame
        next.size.width = min(max(0, next.width), visible.width)
        next.size.height = min(max(HUDMetrics.minCardHeight, next.height), visible.height)
        if next.maxX > visible.maxX {
            next.origin.x = visible.maxX - next.width
        }
        if next.minX < visible.minX {
            next.origin.x = visible.minX
        }
        if next.maxY > visible.maxY {
            next.origin.y = visible.maxY - next.height
        }
        if next.minY < visible.minY {
            next.origin.y = visible.minY
        }
        if next.maxY > visible.maxY {
            next.size.height = max(HUDMetrics.minCardHeight, visible.maxY - next.origin.y)
        }
        if next.maxX > visible.maxX {
            next.size.width = max(0, visible.maxX - next.origin.x)
        }
        return next
    }

    /// Gap a long reply leaves above the bottom of the visible frame before it grows up.
    static let replyFloorMargin: CGFloat = 24

    /// Centered horizontally, a third of the way down, so replies have room to grow below.
    static func launchOrigin(size: NSSize, visibleFrame visible: NSRect) -> NSPoint {
        let centerY = visible.maxY - visible.height / 3
        let y = min(max(centerY - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSPoint(x: visible.midX - size.width / 2, y: y)
    }

    /// The top stays put and the card grows down to the floor. Only what does not fit lifts the top. Past 30 lines, freeze.
    static func frameForReplyGrowth(
        x: CGFloat,
        pinTopMaxY: CGFloat,
        height: CGFloat,
        replyLines: Int,
        lineHeight: CGFloat = replyLineHeight,
        chromeHeight: CGFloat = HUDMetrics.minCardHeight,
        visibleFrame: NSRect? = nil
    ) -> NSRect {
        let visible = replyVisibleLines(replyLines)
        let cappedHeight = cappedCardHeight(
            proposed: height,
            chromeHeight: chromeHeight,
            lineHeight: lineHeight
        )
        let extraUp = replyExtraUpHeight(lines: visible, lineHeight: lineHeight)
        let heightAtDownCap = max(HUDMetrics.minCardHeight, cappedHeight - extraUp)
        var next = NSRect(
            x: x,
            y: pinTopMaxY - heightAtDownCap,
            width: HUDMetrics.cardWidth,
            height: heightAtDownCap
        )
        if let visibleFrame {
            // Grow down from the pinned top to the floor. Only what doesn't fit lifts the top.
            next.size.height = cappedHeight
            next.origin.y = max(pinTopMaxY - cappedHeight, visibleFrame.minY + replyFloorMargin)
        } else if extraUp > 0 {
            next = framePinnedBottom(current: next, height: cappedHeight)
        }
        if let visibleFrame {
            next = clampFrame(next, to: visibleFrame)
        }
        return next
    }

    struct ScrollFadeEdges: Equatable, Sendable {
        var top: Bool
        var bottom: Bool

        static let none = ScrollFadeEdges(top: false, bottom: false)
    }

    struct ScrollPin: Equatable, Sendable {
        var fits: Bool
        var atBottom: Bool
    }


    /// Overlay scroller fade. Fast enough to read as a fade, not a pop.
    static let scrollerFadeDuration: TimeInterval = 0.16
    /// Wait after the last scroll phase before fading the overlay scroller out.
    static let scrollerHideDelay: TimeInterval = 0.35

    /// Short mask into the card glass. Not a second plate.
    static let scrollFadeLength: CGFloat = 16

    /// Chevron is up when the overlay scroller is gone. Inverse while the bar is on screen, including its fade.
    static func expandChevronOpacity(scrollerVisible: Bool) -> CGFloat {
        scrollerVisible ? 0 : 1
    }

    /// Trailing column shared with send/mic: control sits inside the card's `inset` gutter, outside scroll text.

    /// Top fade when scrolled away from the start. Bottom fade when more content remains below.
    /// Short content that fits the viewport gets neither.
    static func scrollFadeEdges(
        offset: CGFloat,
        contentHeight: CGFloat,
        viewport: CGFloat
    ) -> ScrollFadeEdges {
        ScrollFadeEdges(
            top: offset > 0,
            bottom: offset + viewport < contentHeight
        )
    }

    /// Short content that still fits is not "at the tail" for stick-to-bottom.
    static func scrollPin(
        offset: CGFloat,
        contentHeight: CGFloat,
        viewport: CGFloat
    ) -> ScrollPin {
        let fits = contentHeight <= viewport + 1
        if fits {
            return ScrollPin(fits: true, atBottom: true)
        }
        let leftover = contentHeight - offset - viewport
        return ScrollPin(fits: false, atBottom: leftover < 24)
    }

    /// A taller reply is not a scroll. Only a finger on the scroller lets go of the tail.
    static func tailFollow(
        following: Bool,
        fits: Bool,
        atBottom: Bool,
        userScrolling: Bool = false
    ) -> Bool {
        if fits || atBottom { return true }
        return following && !userScrolling
    }

    static func wrappedReplyLines(_ text: String) -> Int {
        wrappedReplyLines(text, width: replyTextWidth, font: replyFont)
    }

    static func wrappedReplyLines(_ text: String, width: CGFloat, font: NSFont) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 1 else { return 0 }
        let ns = nsReplyText(text, font: font)
        let storage = NSTextStorage(attributedString: ns)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let glyphs = manager.numberOfGlyphs
        guard glyphs > 0 else { return 0 }
        var lines = 0
        var index = 0
        while index < glyphs {
            var range = NSRange()
            manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            lines += 1
            index = NSMaxRange(range)
        }
        return lines
    }

    static func styledReply(_ text: String) -> AttributedString {
        AttributedString(nsReplyText(text, font: replyFont))
    }

    private static func nsReplyText(_ text: String, font: NSFont) -> NSAttributedString {
        let markdown = NSMutableAttributedString(ReplyMarkdown.attributed(text))
        let paragraph = NSMutableParagraphStyle()
        let line = PromptLayout.lineHeight(for: font)
        paragraph.minimumLineHeight = line
        paragraph.maximumLineHeight = line
        paragraph.lineBreakMode = .byWordWrapping
        let range = NSRange(location: 0, length: markdown.length)
        if range.length > 0 {
            markdown.addAttribute(.paragraphStyle, value: paragraph, range: range)
            markdown.enumerateAttribute(.font, in: range) { value, run, _ in
                if value == nil {
                    markdown.addAttribute(.font, value: font, range: run)
                }
            }
        }
        return markdown
    }
}

enum HUDLipChrome {
    /// Reference fill, sampled ~RGB(22, 16, 18) on black.
    static let fillTop = NSColor(srgbRed: 22 / 255, green: 16 / 255, blue: 18 / 255, alpha: 1)
    static let fillBottom = NSColor(srgbRed: 42 / 255, green: 22 / 255, blue: 26 / 255, alpha: 1)
    /// Dusty rose from the reference glyphs, not `systemRed`.
    static let ink = NSColor(srgbRed: 0.84, green: 0.51, blue: 0.58, alpha: 1)
    static let dismiss = NSColor.white.withAlphaComponent(0.58)
}

enum HUDErrorLip {
    enum Action: Equatable, Sendable {
        case voice
        case screen
        case accessibility
        case none
    }

    enum Source: Equatable, Sendable {
        case failed
        case blocking
        case screen
        case voice
    }

    struct Message: Equatable, Sendable {
        var text: String
        var action: Action
        var source: Source
    }

    struct State: Equatable, Sendable {
        var phase: Phase
        var errorMessage: String?
        var screenNotice: String?
        var voiceStatus: String?
        var dismissed: Bool
    }

    static let screenPermission = String(localized: "Allow Screen Recording in System Settings")
    static let screenFailed = String(localized: "The screen capture failed.")
    static let accessibilityPermission = String(localized: "Allow Accessibility in System Settings")

    static func message(
        phase: Phase,
        blockingMessage: String?,
        screenNotice: String?,
        voiceStatus: String?,
        dismissed: Bool
    ) -> Message? {
        if case .failed(let text) = phase, !text.isEmpty {
            return Message(text: text, action: .none, source: .failed)
        }
        if phase == .composing, let blocking = blockingMessage, !blocking.isEmpty, !dismissed {
            return Message(text: blocking, action: .none, source: .blocking)
        }
        if let notice = screenNotice, !notice.isEmpty {
            let action: Action
            if notice == screenPermission {
                action = .screen
            } else if notice == accessibilityPermission {
                action = .accessibility
            } else {
                action = .none
            }
            return Message(
                text: notice,
                action: action,
                source: .screen
            )
        }
        if let voice = voiceStatus, !voice.isEmpty {
            return Message(
                text: voice,
                action: VoiceStatusCopy.systemSettingsURL(for: voice) == nil ? .none : .voice,
                source: .voice
            )
        }
        return nil
    }

    static func dismiss(_ state: inout State, blockingMessage: String?) {
        guard let shown = message(
            phase: state.phase,
            blockingMessage: blockingMessage,
            screenNotice: state.screenNotice,
            voiceStatus: state.voiceStatus,
            dismissed: state.dismissed
        ) else {
            return
        }
        state.dismissed = true
        switch shown.source {
        case .failed:
            state.phase = .composing
            state.errorMessage = nil
        case .screen:
            state.screenNotice = nil
        case .voice:
            state.voiceStatus = nil
        case .blocking:
            break
        }
    }

}
