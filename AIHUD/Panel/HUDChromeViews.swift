import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class CardMenuProxy: NSObject {
    let onSettings: () -> Void
    let onDebug: () -> Void

    init(onSettings: @escaping () -> Void, onDebug: @escaping () -> Void) {
        self.onSettings = onSettings
        self.onDebug = onDebug
    }

    @objc func openSettings() {
        onSettings()
    }

    @objc func openDebug() {
        onDebug()
    }
}

final class HUDGlassContainer: NSGlassEffectContainerView {
    var passesThroughGaps = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if passesThroughGaps, hit === self { return nil }
        return hit
    }
}

final class HUDChromeWrapper: NSView {
    var plate: NSView?
    var lip: NSView?
    var hasLip = false
    var cardHeight: CGFloat = HUDMetrics.minCardHeight
    var usesSplit = false
    var margin = NSEdgeInsetsZero
    var splitCapsuleHeight: CGFloat = HUDMetrics.rowHeight
    var splitLeading: [NSView] = []
    var splitTrailing: [NSView] = []
    private var departingPills: [NSView] = []
    private var pillSlide: PillSlide?
    private(set) var isPouring = false
    private(set) var pourOpening = true
    private var pourStart: TimeInterval = 0
    private var pourLatched = false
    private var pourFromFrames: [CGRect]?
    private var livePillFrames: [CGRect] = []
    private var handoffFrom: [CGRect]?
    private var handoffStart: TimeInterval = 0
    private var handoffScale: CGFloat = 1
    private var handoffSpacing: CGFloat = 0

    private struct PillSlide {
        var from: [ObjectIdentifier: NSRect]
        var start: TimeInterval
        var duration: TimeInterval
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { return nil }

    func embedPlateAndLip() {
        if let lip, lip.superview !== self {
            lip.removeFromSuperview()
            addSubview(lip, positioned: .below, relativeTo: nil)
        }
        if let plate {
            if plate.superview !== self {
                plate.removeFromSuperview()
                addSubview(plate, positioned: .above, relativeTo: lip)
            } else if let lip {
                addSubview(plate, positioned: .above, relativeTo: lip)
            }
        }
        plate?.autoresizingMask = []
        lip?.autoresizingMask = []
        needsLayout = true
    }

    override func layout() {
        if usesSplit {
            layoutSplit()
            return
        }
        super.layout()
        let placed = HUDLayout.lipPlacement(
            windowHeight: bounds.height,
            cardHeight: cardHeight,
            cardWidth: bounds.width,
            hasLip: hasLip
        )
        let showing = placed.revealed > 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lip?.isHidden = !showing
        lip?.frame = placed.lip
        if showing {
            layer?.cornerRadius = 0
            layer?.masksToBounds = false
        } else {
            layer?.mask = nil
            layer?.cornerRadius = HUDMetrics.cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }
        plate?.frame = placed.plate
        (plate as? CardGlassView)?.lipRevealed = placed.revealed
        CATransaction.commit()
        plate?.layoutSubtreeIfNeeded()
        (plate as? CardGlassView)?.containKeyFringe()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if usesSplit, hit === self { return nil }
        return hit
    }

    func pointHitsSplitChrome(_ point: NSPoint) -> Bool {
        guard usesSplit else { return bounds.contains(point) }
        var frames = splitFrames()
        if isPouring, livePillFrames.count == frames.pills.count {
            frames.pills = livePillFrames
        }
        return HUDSplitChromeLayout.pointHitsChrome(point, frames: frames, splitEnabled: true)
    }

    func beginPour(opening: Bool) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce {
            cancelPour()
            return
        }
        pourFromFrames = isPouring ? livePillFrames : nil
        isPouring = true
        pourOpening = opening
        pourStart = Date().timeIntervalSinceReferenceDate
        if !opening { pourLatched = false }
        (window as? HUDPanel)?.beginChromeTick(duration: HUDFrameMotion.pourOpenTick)
    }

    func handoffPourToGrowth() {
        guard isPouring else { return }
        handoffFrom = livePillFrames
        handoffScale = plate.map { view in
            let settled = max(view.bounds.width, 1)
            return view.frame.width / settled
        } ?? 1
        handoffSpacing = (superview as? NSGlassEffectContainerView)?.spacing ?? 0
        handoffStart = Date().timeIntervalSinceReferenceDate
        isPouring = false
        pourLatched = true
        pourFromFrames = nil
    }

    func cancelPour() {
        isPouring = false
        pourLatched = false
        pourFromFrames = nil
        livePillFrames = []
        (plate as? CardGlassView)?.holdsSettledHost = false
        (superview as? NSGlassEffectContainerView)?.spacing = HUDMaterial.glassContainerSpacing
    }

    func retirePill(_ view: NSView) {
        guard !departingPills.contains(where: { $0 === view }) else { return }
        departingPills.append(view)
    }

    func beginPillSlide() {
        let duration = HUDFrameMotion.duration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if duration == 0 {
            pillSlide = nil
            finishDepartingPills()
            return
        }
        var from: [ObjectIdentifier: NSRect] = [:]
        for view in splitLeading + splitTrailing + departingPills where view.frame.width > 1 {
            from[ObjectIdentifier(view)] = view.frame
        }
        pillSlide = PillSlide(
            from: from,
            start: Date().timeIntervalSinceReferenceDate,
            duration: duration
        )
    }

    func cancelPillSlide() {
        pillSlide = nil
        finishDepartingPills()
    }

    private func layoutSplit() {
        super.layout()
        wantsLayer = true
        layer?.mask = nil
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        let frames = splitFrames()
        let views = splitLeading + splitTrailing
        if !isPouring, pillSlide == nil, pillWidthsNeedSlide(views: views, frames: frames.pills) {
            beginPillSlide()
            (window as? HUDPanel)?.beginChromeTick()
        }
        let eased = isPouring ? 1 : pillSlideProgress()
        let poured = isPouring ? pouredFrames(rest: frames.pills, plate: frames.placement.plate) : nil
        let handed = poured == nil ? handoffFrames(rest: frames.pills, plate: frames.placement.plate) : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let plateFrame = poured?.plate ?? handed?.plate ?? frames.placement.plate
        let radius = HUDSplitChromeLayout.capsuleCornerRadius(height: plateFrame.height)
        plate?.frame = plateFrame
        if let glass = plate as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
        if let poured {
            (plate as? CardGlassView)?.holdsSettledHost = true
            (plate as? CardGlassView)?.settledHostSize = frames.placement.plate.size
            let spacing = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                ? HUDMaterial.glassContainerSpacing
                : poured.spacing
            (superview as? NSGlassEffectContainerView)?.spacing = spacing
        } else if let handed {
            (plate as? CardGlassView)?.holdsSettledHost = handed.scale < 0.995
            (plate as? CardGlassView)?.settledHostSize = frames.placement.plate.size
            (superview as? NSGlassEffectContainerView)?.spacing = handed.spacing
        } else {
            (plate as? CardGlassView)?.holdsSettledHost = false
            (superview as? NSGlassEffectContainerView)?.spacing = HUDMaterial.glassContainerSpacing
        }
        applyCapsuleRadius(radius)
        let revealed = frames.placement.revealed
        lip?.isHidden = revealed < 0.5
        if revealed > 0.5 {
            lip?.frame = CGRect(
                x: frames.placement.lip.minX,
                y: frames.placement.plate.minY - revealed,
                width: frames.placement.lip.width,
                height: revealed
            )
        }
        (lip as? ErrorLipBand)?.setCopyOpacity(HUDSplitChromeLayout.lipCopyOpacity(revealed: revealed))
        let rowY = frames.pills.first?.origin.y
        let pillTargets = poured?.pills ?? handed?.pills ?? frames.pills
        livePillFrames = pillTargets
        for (view, frame) in zip(views, pillTargets) {
            if poured != nil {
                placePill(view, target: frame, eased: 1)
            } else {
                placePill(view, target: frame, eased: eased)
            }
        }
        for view in departingPills {
            let from = pillSlide?.from[ObjectIdentifier(view)] ?? view.frame
            var frame = from
            if let rowY { frame.origin.y = rowY }
            view.frame = frame
            view.alphaValue = 1 - eased
        }
        if eased >= 1 {
            finishDepartingPills()
        }
        CATransaction.commit()
        if let card = plate as? CardGlassView {
            card.lipRevealed = 0
            card.masksAncestors = false
        }
        plate?.layoutSubtreeIfNeeded()
    }

    private func pillWidthsNeedSlide(views: [NSView], frames: [NSRect]) -> Bool {
        zip(views, frames).contains { view, frame in
            view.frame.width > 1 && abs(view.frame.width - frame.width) > 1
        }
    }

    private func pillSlideProgress() -> CGFloat {
        guard let slide = pillSlide else { return 1 }
        let linear = (Date().timeIntervalSinceReferenceDate - slide.start) / slide.duration
        if linear >= 1 {
            pillSlide = nil
            return 1
        }
        return CGFloat(HUDFrameMotion.easeInOut(linear))
    }

    private func placePill(_ view: NSView, target: NSRect, eased: CGFloat) {
        let id = ObjectIdentifier(view)
        let frame: NSRect
        let alpha: CGFloat
        if let from = pillSlide?.from[id], eased < 1 {
            frame = NSRect(
                x: from.origin.x + (target.origin.x - from.origin.x) * eased,
                y: target.origin.y,
                width: from.width + (target.width - from.width) * eased,
                height: target.height
            )
            alpha = 1
        } else if pillSlide != nil, pillSlide?.from[id] == nil, eased < 1 {
            frame = target
            alpha = eased
        } else {
            frame = target
            alpha = 1
        }
        view.frame = frame
        view.alphaValue = alpha
        let pillRadius = min(frame.width, frame.height) / 2
        if let glass = view as? NSGlassEffectView, abs(glass.cornerRadius - pillRadius) > 0.5 {
            glass.cornerRadius = pillRadius
        }
        if abs((view.layer?.cornerRadius ?? -1) - pillRadius) > 0.5 {
            view.layer?.cornerRadius = pillRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }

    private func pouredFrames(rest: [CGRect], plate: CGRect) -> (pills: [CGRect], plate: CGRect, spacing: CGFloat)? {
        guard isPouring, !rest.isEmpty else { return nil }
        let elapsed = Date().timeIntervalSinceReferenceDate - pourStart
        if elapsed >= HUDFrameMotion.pourOpenTick {
            isPouring = false
            pourLatched = false
            pourFromFrames = nil
            return nil
        }
        let ranks = HUDFrameMotion.pourRanks(midXs: rest.map(\.midX), cardWidth: bounds.width)
        let pills: [CGRect] = rest.enumerated().map { index, end in
            let tuck = HUDFrameMotion.tuckedPillFrame(rest: end, plate: plate, cardWidth: bounds.width)
            if let prior = pourFromFrames, prior.indices.contains(index) {
                let progress = pourOpening
                    ? HUDFrameMotion.pourSpring(elapsed: elapsed)
                    : HUDFrameMotion.pourDismissProgress(elapsed: elapsed)
                return HUDFrameMotion.pouredPillFrame(
                    from: prior[index],
                    to: pourOpening ? end : tuck,
                    presentation: progress
                )
            }
            // Presentation is openness in both directions, so it always runs tuck to seat.
            let openness = HUDFrameMotion.pourPresentation(
                elapsed: elapsed,
                delay: HUDFrameMotion.pourDelay(rank: ranks[index]),
                opening: pourOpening
            )
            return HUDFrameMotion.pouredPillFrame(from: tuck, to: end, presentation: openness)
        }
        let slowest = pills.map { plate.minY - $0.maxY }.min() ?? HUDSplitChromeLayout.pillGap
        var spacing = HUDFrameMotion.pourSpacing(slowestVerticalGap: slowest)
        if pourOpening, slowest >= HUDSplitChromeLayout.pillGap {
            pourLatched = true
        }
        if pourLatched { spacing = 0 }
        let lead = HUDFrameMotion.pourPresentation(elapsed: elapsed, delay: 0, opening: pourOpening)
        let scale = HUDFrameMotion.pourCapsuleScale(presentation: lead)
        return (pills, HUDFrameMotion.scaledPlateFrame(plate: plate, scale: scale), spacing)
    }

    private func handoffFrames(rest: [CGRect], plate: CGRect) -> (pills: [CGRect], plate: CGRect, scale: CGFloat, spacing: CGFloat)? {
        guard let from = handoffFrom, from.count == rest.count else { return nil }
        let duration = HUDFrameMotion.duration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let linear = duration == 0 ? 1 : (Date().timeIntervalSinceReferenceDate - handoffStart) / duration
        if linear >= 1 {
            handoffFrom = nil
            return nil
        }
        let t = CGFloat(HUDFrameMotion.easeInOut(linear))
        let pills = zip(from, rest).map { start, end in
            HUDFrameMotion.pouredPillFrame(from: start, to: end, presentation: t)
        }
        let scale = handoffScale + (1 - handoffScale) * t
        let width = plate.width * scale
        let height = plate.height * scale
        let frame = CGRect(x: plate.midX - width / 2, y: plate.maxY - height, width: width, height: height)
        return (pills, frame, scale, handoffSpacing * (1 - t))
    }

    private func applyCapsuleRadius(_ radius: CGFloat) {
        plate?.layer?.cornerRadius = radius
        plate?.layer?.cornerCurve = .continuous
        plate?.layer?.masksToBounds = true
        let anchor = (plate as? NSGlassEffectView)?.contentView ?? plate?.subviews.first
        anchor?.layer?.cornerRadius = radius
        anchor?.layer?.masksToBounds = true
        if let prompt = anchor as? PromptAnchorView {
            prompt.host.layer?.cornerRadius = radius
            prompt.host.layer?.masksToBounds = true
        }
    }

    private func finishDepartingPills() {
        for view in departingPills {
            view.removeFromSuperview()
        }
        departingPills.removeAll()
    }

    /// The card sits inside this margin. Frames come back in view space.
    private func splitFrames() -> HUDSplitChromeLayout.Frames {
        let frames = HUDSplitChromeLayout.frames(
            splitEnabled: true,
            settledCapsuleHeight: splitCapsuleHeight,
            panelHeight: bounds.height - margin.top - margin.bottom,
            showLip: hasLip,
            cardWidth: bounds.width - margin.left - margin.right,
            leadingWidths: splitLeading.map(measuredPillWidth),
            trailingWidths: splitTrailing.map(measuredPillWidth)
        )
        let dx = margin.left
        let dy = margin.bottom
        return HUDSplitChromeLayout.Frames(
            placement: HUDLayout.LipPlacement(
                plate: frames.placement.plate.offsetBy(dx: dx, dy: dy),
                lip: frames.placement.lip.offsetBy(dx: dx, dy: dy),
                revealed: frames.placement.revealed
            ),
            pills: frames.pills.map { $0.offsetBy(dx: dx, dy: dy) }
        )
    }

    private func measuredPillWidth(_ view: NSView) -> CGFloat {
        view.layoutSubtreeIfNeeded()
        let fitted = view.fittingSize.width
        let width = (fitted > 1 && fitted < 2_000) ? fitted : view.bounds.width
        return max(HUDSplitChromeLayout.pillHeight, ceil(width))
    }
}

final class ErrorLipBand: NSView {
    private let host: ClickThroughHosting<ErrorLipContent>
    private let fill = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        host = ClickThroughHosting(
            rootView: ErrorLipContent(text: "", action: .none, onTap: {}, onDismiss: {})
        )
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = HUDLayout.lipCorner
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
        fill.colors = [
            HUDLipChrome.fillTop.cgColor,
            HUDLipChrome.fillBottom.cgColor
        ]
        fill.startPoint = CGPoint(x: 0.5, y: 1)
        fill.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(fill)
        host.safeAreaRegions = []
        addSubview(host)
    }

    required init?(coder: NSCoder) { return nil }

    func setCopyOpacity(_ value: CGFloat) {
        host.alphaValue = value
    }

    func apply(
        _ message: HUDErrorLip.Message,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        host.rootView = ErrorLipContent(
            text: message.text,
            action: message.action,
            onTap: onTap,
            onDismiss: onDismiss
        )
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = HUDLayout.lipCorner
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
        fill.frame = bounds
        host.frame = bounds
    }

    override var isOpaque: Bool { false }
}

final class ClickThroughHosting<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Sits between the glass and the SwiftUI host. The glass shrink-wraps an NSHostingView
/// onto the AppKit bottom. This view fills the plate, and the host keeps its own height
/// with its top on the plate top, so the field cannot drop while the window eases.
final class PromptAnchorView: NSView {
    let host: NSView

    init(host: NSView) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        clipsToBounds = true
        host.autoresizingMask = []
        if host.superview !== self {
            host.removeFromSuperview()
            addSubview(host)
        }
    }

    required init?(coder: NSCoder) { return nil }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        let fitted = host.fittingSize.height
        // The 10_000pt measure proposal is not a real card. Using it pins the
        // prompt thousands of points above the clip, so the glass looks empty.
        let content = (fitted > 1 && fitted < HUDLayout.hostingFitSize.height - 1)
            ? fitted
            : bounds.height
        let next = HUDFrameMotion.promptHostFrame(
            plateWidth: bounds.width,
            plateHeight: bounds.height,
            contentHeight: content
        )
        guard host.frame != next else { return }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = next
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }
}

/// Keeps the window frame from painting a square behind the rounded plate.
final class CardGlassView: NSGlassEffectView {
    var lipRevealed: CGFloat = 0
    var masksAncestors = true
    var holdsSettledHost = false
    var settledHostSize: CGSize = .zero
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        pinContentToPlate()
        containKeyFringe()
    }

    /// The glass holder follows this view, not the SwiftUI fitting size.
    private func pinContentToPlate() {
        guard let content = contentView else { return }
        let holder = content.superview
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        if let holder, holder !== self {
            holder.clipsToBounds = true
            if holder.frame != bounds {
                holder.frame = bounds
            }
        }
        let parent = (holder != nil && holder !== self) ? holder! : self
        content.clipsToBounds = true
        let hostFrame: CGRect
        if holdsSettledHost, settledHostSize.width > 1, settledHostSize.height > 1 {
            hostFrame = CGRect(
                x: (parent.bounds.width - settledHostSize.width) / 2,
                y: parent.bounds.height - settledHostSize.height,
                width: settledHostSize.width,
                height: min(settledHostSize.height, parent.bounds.height)
            )
        } else {
            hostFrame = parent.bounds
        }
        if content.frame != hostFrame {
            content.frame = hostFrame
        }
        NSAnimationContext.endGrouping()
        content.layoutSubtreeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
        containKeyFringe()
    }

    func containKeyFringe() {
        applyClearRoundedMask(to: self)
        guard masksAncestors else { return }
        var node = superview
        while let view = node {
            applyClearRoundedMask(to: view)
            if view === window?.contentView {
                if let frameView = view.superview {
                    applyClearRoundedMask(to: frameView)
                }
                break
            }
            node = view.superview
        }
    }

    private func applyClearRoundedMask(to view: NSView) {
        view.wantsLayer = true
        view.focusRingType = .none
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if lipRevealed > 0.5, view !== self {
            HUDLayout.applyLipWindowMask(to: view, revealed: lipRevealed)
            return
        }
        view.layer?.mask = nil
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

final class PillGlassView: NSGlassEffectView {
    var pressHighlight = true
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        pinContentToPill()
        let radius = min(bounds.width, bounds.height) / 2
        if abs(cornerRadius - radius) > 0.5 {
            cornerRadius = radius
        }
        if abs((layer?.cornerRadius ?? -1) - radius) > 0.5 {
            layer?.cornerRadius = radius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }
    }

    private func pinContentToPill() {
        guard let content = contentView else { return }
        let holder = content.superview
        if let holder, holder !== self {
            holder.frame = bounds
        }
        let parent = (holder != nil && holder !== self) ? holder! : self
        content.frame = parent.bounds
    }
}

final class SolidPillView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content?.frame = bounds
    }

    private var content: NSView? { subviews.first }

    func embed(_ child: NSView) {
        if child.superview !== self {
            child.removeFromSuperview()
            addSubview(child)
        }
    }
}

final class SolidCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = HUDMetrics.cornerRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { return nil }

    func embed(_ child: NSView) {
        if child.superview !== self {
            addSubview(child)
        }
        child.frame = bounds
        child.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        for child in subviews {
            if child.frame != bounds {
                child.frame = bounds
            }
            child.layoutSubtreeIfNeeded()
        }
    }
}
