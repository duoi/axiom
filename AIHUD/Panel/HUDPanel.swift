import AppKit

struct BoundShortcut: Equatable, Sendable {
    var keyCode: UInt16
    var control: Bool
    var command: Bool
    var option: Bool
    var shift: Bool
}

enum HUDEscape {
    static let keyCode: UInt16 = 53

    /// The hide shortcut dismisses whenever the panel is key. The first responder does not matter.
    static func shouldDismiss(
        keyCode: UInt16,
        control: Bool = false,
        command: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        panelIsKey: Bool,
        menuTracking: Bool,
        hasAttachedSheet: Bool,
        isComposing: Bool,
        bindings: [HUDShortcut: [BoundShortcut]] = HUDShortcuts.defaults
    ) -> Bool {
        guard !isComposing else { return false }
        return HUDShortcuts.action(
            keyCode: keyCode,
            control: control,
            command: command,
            option: option,
            shift: shift,
            panelIsKey: panelIsKey,
            menuTracking: menuTracking,
            hasAttachedSheet: hasAttachedSheet,
            bindings: bindings
        ) == .hide
    }
}

enum HUDShortcut: Equatable {
    case hide
    case send
    case newline
    case cyclePreset
    case cycleCapture
    case addContext
    case toggleIncognito
    case toggleDictation
}

enum HUDShortcuts {
    /// Keypad Enter follows Return when Send is still plain Return.
    private static let keypadEnter: UInt16 = 76

    static let defaults: [HUDShortcut: [BoundShortcut]] = [
        .hide: [plain(53)],
        .send: [plain(36)],
        .newline: [
            BoundShortcut(keyCode: 36, control: false, command: false, option: true, shift: false),
            BoundShortcut(keyCode: 36, control: false, command: false, option: false, shift: true),
        ],
        .cyclePreset: [control(0)],
        .cycleCapture: [control(1)],
        .addContext: [control(8)],
        .toggleIncognito: [control(15)],
        .toggleDictation: [control(39)],
    ]

    static func action(
        keyCode: UInt16,
        control: Bool,
        command: Bool,
        option: Bool,
        shift: Bool,
        panelIsKey: Bool,
        menuTracking: Bool,
        hasAttachedSheet: Bool,
        isComposing: Bool = false,
        bindings: [HUDShortcut: [BoundShortcut]] = defaults
    ) -> HUDShortcut? {
        guard panelIsKey, !menuTracking, !hasAttachedSheet, !isComposing else { return nil }
        let pressed = BoundShortcut(
            keyCode: keyCode,
            control: control,
            command: command,
            option: option,
            shift: shift
        )
        let order: [HUDShortcut] = [
            .newline, .send, .hide, .cyclePreset, .cycleCapture, .addContext, .toggleIncognito, .toggleDictation,
        ]
        for kind in order where bindings[kind]?.contains(pressed) == true {
            return kind
        }
        if pressed == plain(keypadEnter), bindings[.send]?.contains(plain(36)) == true {
            return .send
        }
        return nil
    }

    private static func plain(_ keyCode: UInt16) -> BoundShortcut {
        BoundShortcut(keyCode: keyCode, control: false, command: false, option: false, shift: false)
    }

    private static func control(_ keyCode: UInt16) -> BoundShortcut {
        BoundShortcut(keyCode: keyCode, control: true, command: false, option: false, shift: false)
    }
}

enum HUDCaptureCycle {
    /// Control-S: arm the current target, switch Screen/Window, then disarm.
    static func advance(
        armed: Bool,
        target: CaptureTarget,
        toggledOption: Bool
    ) -> (armed: Bool, target: CaptureTarget, toggledOption: Bool) {
        if !armed {
            return (true, target, false)
        }
        if !toggledOption {
            return (true, target == .screen ? .window : .screen, true)
        }
        return (false, target, false)
    }
}

/// Quick panel show/hide fade. Same duration as the overlay scroller.
enum HUDPanelFade {
    static let duration: TimeInterval = HUDLayout.scrollerFadeDuration

    static func animationDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : duration
    }
}

/// Window-frame resize. Same 160ms ease as the panel fade. Reduce Motion is instant.
enum HUDFrameMotion {
    static func duration(reduceMotion: Bool) -> TimeInterval {
        HUDPanelFade.animationDuration(reduceMotion: reduceMotion)
    }

    /// Symmetric ease in-out. Halfway in time is halfway across the rect.
    static func easeInOut(_ linear: Double) -> Double {
        let t = min(1, max(0, linear))
        return t * t * (3 - 2 * t)
    }

    /// Same ease as the window, for a single length such as the capsule height.
    static func scalar(from start: CGFloat, to end: CGFloat, linearProgress: Double) -> CGFloat {
        let t = CGFloat(easeInOut(linearProgress))
        if t <= 0 { return start }
        if t >= 1 { return end }
        return start + (end - start) * t
    }

    /// Tops within 1pt share one top. A raised reply (past 15 lines) is the case that moves it.
    static let topPinTolerance: CGFloat = 1

    static func pinsTop(from start: NSRect, to end: NSRect) -> Bool {
        abs(start.maxY - end.maxY) <= topPinTolerance
    }

    static func frame(from start: NSRect, to end: NSRect, linearProgress: Double) -> NSRect {
        let t = CGFloat(easeInOut(linearProgress))
        if t <= 0 { return start }
        if t >= 1 { return end }
        let x = start.origin.x + (end.origin.x - start.origin.x) * t
        let width = start.width + (end.width - start.width) * t
        let height = start.height + (end.height - start.height) * t
        if pinsTop(from: start, to: end) {
            return NSRect(x: x, y: start.maxY - height, width: width, height: height)
        }
        return NSRect(
            x: x,
            y: start.origin.y + (end.origin.y - start.origin.y) * t,
            width: width,
            height: height
        )
    }

    /// Non-flipped plate. The host keeps its fitting height and its top on the plate top.
    /// A taller reply hangs below the plate (negative y) until the window catches up.
    /// A shorter reply leaves empty plate below it. Spare room is never above the field.
    static func promptHostFrame(
        plateWidth: CGFloat,
        plateHeight: CGFloat,
        contentHeight: CGFloat
    ) -> NSRect {
        let height = contentHeight > 1 ? contentHeight : plateHeight
        return NSRect(x: 0, y: plateHeight - height, width: plateWidth, height: height)
    }

    static let pourResponse: TimeInterval = 0.50
    static let pourDamping: Double = 0.70
    static let pourOverlap: CGFloat = 22
    static let pourGather: CGFloat = 0.42
    static let pourBridge: CGFloat = 32
    static let pourStagger: TimeInterval = 0.032
    static let pourOpenTick: TimeInterval = 0.64
    static let pourDismissFadeDelay: TimeInterval = 0.20
    static let pourScaleStart: CGFloat = 0.96
    static let pourDismissDuration: TimeInterval = 0.24

    /// Underdamped step from 0 toward 1. It crosses 1, then settles.
    static func pourSpring(elapsed: TimeInterval) -> CGFloat {
        let t = max(0, elapsed)
        let omega = 2 * Double.pi / pourResponse
        let decay = exp(-pourDamping * omega * t)
        let damped = omega * sqrt(max(0, 1 - pourDamping * pourDamping))
        let coast = cos(damped * t) + (pourDamping * omega / damped) * sin(damped * t)
        return CGFloat(1 - decay * coast)
    }

    static func pourDelay(rank: Int) -> TimeInterval {
        TimeInterval(min(max(rank, 0), 2)) * pourStagger
    }

    /// How open the row is: 0 tucked, 1 seated. Opening springs after the delay.
    /// Dismiss eases in with no spring, so nothing bounces while the card fades.
    static func pourPresentation(elapsed: TimeInterval, delay: TimeInterval, opening: Bool) -> CGFloat {
        if elapsed < delay { return opening ? 0 : 1 }
        if opening {
            return pourSpring(elapsed: elapsed - delay)
        }
        return 1 - pourDismissProgress(elapsed: elapsed - delay)
    }

    static func pourDismissProgress(elapsed: TimeInterval) -> CGFloat {
        let unit = min(1, max(0, elapsed / pourDismissDuration))
        return CGFloat(unit * unit)
    }

    static func pourRanks(midXs: [CGFloat], cardWidth: CGFloat) -> [Int] {
        let center = cardWidth / 2
        let ordered = midXs.enumerated().sorted { lhs, rhs in
            let left = abs(lhs.element - center)
            let right = abs(rhs.element - center)
            if abs(left - right) > 0.5 { return left < right }
            return lhs.element < rhs.element
        }
        var ranks = Array(repeating: 0, count: midXs.count)
        for (rank, item) in ordered.enumerated() {
            ranks[item.offset] = rank
        }
        return ranks
    }

    /// Pill starts inside the capsule, pulled toward the middle of the card.
    static func tuckedPillFrame(rest: CGRect, plate: CGRect, cardWidth: CGFloat) -> CGRect {
        let center = cardWidth / 2
        let gathered = rest.midX + (center - rest.midX) * pourGather
        let x = gathered - rest.width / 2
        let y = plate.minY + pourOverlap - rest.height
        return CGRect(x: x, y: y, width: rest.width, height: rest.height)
    }

    static func pouredPillFrame(from start: CGRect, to end: CGRect, presentation: CGFloat) -> CGRect {
        CGRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * presentation,
            y: start.origin.y + (end.origin.y - start.origin.y) * presentation,
            width: end.width,
            height: end.height
        )
    }

    /// High while the row still overlaps the capsule. Zero once the slowest pill has opened the rest gap.
    static func pourSpacing(slowestVerticalGap: CGFloat) -> CGFloat {
        let opening = -pourOverlap
        let span = HUDSplitChromeLayout.pillGap - opening
        let traveled = min(span, max(0, slowestVerticalGap - opening))
        return pourBridge * (1 - traveled / span)
    }

    static func pourCapsuleScale(presentation: CGFloat) -> CGFloat {
        pourScaleStart + (1 - pourScaleStart) * presentation
    }

    static func scaledPlateFrame(plate: CGRect, scale: CGFloat) -> CGRect {
        let width = plate.width * scale
        let height = plate.height * scale
        return CGRect(
            x: plate.midX - width / 2,
            y: plate.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func matches(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }
}

final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var menuTracking = false
    private var didPlace = false
    private var replyPinTopMaxY: CGFloat?
    private let cardWidth: CGFloat = HUDMetrics.cardWidth
    /// Transparent room around the card so the New UI open spring is not clipped.
    /// Card math stays in card space. Only the window frame carries the margin.
    var chromeMargin = NSEdgeInsetsZero {
        didSet {
            guard !NSEdgeInsetsEqual(oldValue, chromeMargin) else { return }
            let card = Self.card(in: frame, margin: oldValue)
            setFrame(Self.window(around: card, margin: chromeMargin), display: false)
        }
    }
    private var fadeToken = 0
    private(set) var isFadingOut = false
    var onFrameStep: (() -> Void)?
    private var frameTimer: Timer?
    private var frameAnim: FrameAnim?

    private struct FrameAnim {
        var from: NSRect
        var to: NSRect
        var fromCapsule: CGFloat
        var toCapsule: CGFloat
        var start: TimeInterval
        var duration: TimeInterval
    }

    private var chromeTick: (start: TimeInterval, duration: TimeInterval)?

    var isAnimatingFrame: Bool { frameAnim != nil }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEscapeEvent(event) { return true }
        if menuTracking { return super.performKeyEquivalent(with: event) }
        guard let action = EditCommands.action(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        if let field = promptField() {
            makeFirstResponder(field)
            if NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleEscapeEvent(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult
    func handleEscapeEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard HUDEscape.shouldDismiss(
            keyCode: event.keyCode,
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            panelIsKey: isKeyWindow,
            menuTracking: menuTracking,
            hasAttachedSheet: attachedSheet != nil,
            isComposing: isComposingInput,
            bindings: CardShortcutBindings.current()
        ) else {
            return false
        }
        onCancel?()
        return true
    }

    var isComposingInput: Bool {
        (firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
    }

    private func promptField() -> NSTextField? {
        var queue = contentView?.subviews ?? []
        while let view = queue.popLast() {
            if let field = view as? NSTextField { return field }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    override func cancelOperation(_ sender: Any?) {
        if attachedSheet != nil {
            super.cancelOperation(sender)
            return
        }
        if menuTracking || isComposingInput { return }
        onCancel?()
    }

    func centerOnMouseScreen(height: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: cardWidth, height: max(HUDMetrics.minCardHeight, height))
        let origin = HUDLayout.launchOrigin(size: size, visibleFrame: visible)
        cancelFrameAnimation()
        didPlace = false
        replyPinTopMaxY = nil
        setCardFrame(NSRect(origin: origin, size: size), display: true)
        didPlace = true
        invalidateShadow()
    }

    func resizeForReply(
        to height: CGFloat,
        replyLines: Int,
        chromeHeight: CGFloat = HUDMetrics.minCardHeight,
        targetCapsule: CGFloat? = nil,
        shownCapsule: CGFloat? = nil,
        animated: Bool
    ) {
        let current = presentedFrame()
        if replyPinTopMaxY == nil {
            replyPinTopMaxY = current.maxY
        }
        let visible = screen?.visibleFrame
        var next = HUDLayout.frameForReplyGrowth(
            x: current.origin.x,
            pinTopMaxY: replyPinTopMaxY ?? current.maxY,
            height: height,
            replyLines: replyLines,
            chromeHeight: chromeHeight,
            visibleFrame: visible
        )
        let targetCap = targetCapsule ?? 0
        if let anim = frameAnim,
           HUDFrameMotion.matches(anim.to, next),
           abs(anim.toCapsule - targetCap) < 0.5 {
            return
        }
        if !didPlace {
            next.origin = cardFrame.origin
            finishFrameAnimation(at: next)
            return
        }
        if HUDFrameMotion.matches(current, next), targetCapsule == nil || abs((shownCapsule ?? targetCap) - targetCap) < 0.5 {
            finishFrameAnimation(at: next)
            return
        }
        let duration = animated
            ? HUDFrameMotion.duration(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            : 0
        if duration == 0 {
            finishFrameAnimation(at: next)
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        let fromCap: CGFloat
        if let anim = frameAnim {
            let linear = min(1, (now - anim.start) / anim.duration)
            fromCap = HUDFrameMotion.scalar(from: anim.fromCapsule, to: anim.toCapsule, linearProgress: linear)
        } else {
            fromCap = shownCapsule ?? targetCap
        }
        frameAnim = FrameAnim(
            from: current,
            to: next,
            fromCapsule: fromCap,
            toCapsule: targetCap,
            start: now,
            duration: duration
        )
        if !HUDFrameMotion.matches(cardFrame, current) {
            setCardFrame(current, display: false)
        }
        startFrameTimer()
    }

    /// Capsule height on this frame. Falls back to the settled height once the ease ends.
    func displayedCapsuleHeight(fallback: CGFloat) -> CGFloat {
        guard let anim = frameAnim else { return fallback }
        let linear = (Date().timeIntervalSinceReferenceDate - anim.start) / anim.duration
        if linear >= 1 { return anim.toCapsule }
        return HUDFrameMotion.scalar(from: anim.fromCapsule, to: anim.toCapsule, linearProgress: linear)
    }

    /// Same timer as the window ease, for pill slides that do not change the window size.
    func beginChromeTick(duration: TimeInterval? = nil) {
        let resolved = duration ?? HUDFrameMotion.duration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        guard resolved > 0 else { return }
        chromeTick = (Date().timeIntervalSinceReferenceDate, resolved)
        startFrameTimer()
    }

    var cardFrame: NSRect { Self.card(in: frame, margin: chromeMargin) }

    private static func card(in window: NSRect, margin: NSEdgeInsets) -> NSRect {
        NSRect(
            x: window.minX + margin.left,
            y: window.minY + margin.bottom,
            width: window.width - margin.left - margin.right,
            height: window.height - margin.top - margin.bottom
        )
    }

    private static func window(around card: NSRect, margin: NSEdgeInsets) -> NSRect {
        NSRect(
            x: card.minX - margin.left,
            y: card.minY - margin.bottom,
            width: card.width + margin.left + margin.right,
            height: card.height + margin.top + margin.bottom
        )
    }

    private func setCardFrame(_ card: NSRect, display: Bool) {
        setFrame(Self.window(around: card, margin: chromeMargin), display: display)
    }

    private func presentedFrame() -> NSRect {
        guard let anim = frameAnim else { return cardFrame }
        let linear = (Date().timeIntervalSinceReferenceDate - anim.start) / anim.duration
        if linear >= 1 { return anim.to }
        return HUDFrameMotion.frame(from: anim.from, to: anim.to, linearProgress: linear)
    }

    private func finishFrameAnimation(at rect: NSRect) {
        frameAnim = nil
        setCardFrame(rect, display: true)
        invalidateShadow()
        if chromeTick == nil {
            stopFrameTimer()
        }
    }

    private func cancelFrameAnimation() {
        frameAnim = nil
        chromeTick = nil
        stopFrameTimer()
    }

    private func startFrameTimer() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepFrameAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func stepFrameAnimation() {
        let now = Date().timeIntervalSinceReferenceDate
        if let anim = frameAnim {
            let linear = (now - anim.start) / anim.duration
            if linear >= 1 {
                frameAnim = nil
                setCardFrame(anim.to, display: false)
                invalidateShadow()
            } else {
                let rect = HUDFrameMotion.frame(from: anim.from, to: anim.to, linearProgress: linear)
                setCardFrame(rect, display: false)
            }
        }
        if let tick = chromeTick {
            let linear = (now - tick.start) / tick.duration
            if linear >= 1 {
                chromeTick = nil
            }
        }
        onFrameStep?()
        displayIfNeeded()
        if frameAnim == nil, chromeTick == nil {
            stopFrameTimer()
        }
    }

    func reveal() {
        fadeToken += 1
        let token = fadeToken
        isFadingOut = false
        let duration = HUDPanelFade.animationDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.fadeToken == token else { return }
                    self.alphaValue = 1
                }
            }
        }
    }

    func fadeOut(delay: TimeInterval = 0, completion: @escaping @Sendable () -> Void) {
        guard isVisible else {
            completion()
            return
        }
        fadeToken += 1
        let token = fadeToken
        isFadingOut = true
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = HUDPanelFade.animationDuration(reduceMotion: reduce)
        // Drop key so ESC / typing do not stick on a vanishing card.
        resignKey()
        let fade = { [weak self] in
            guard let self, self.fadeToken == token else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                self.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.fadeToken == token else { return }
                        self.orderOut(nil)
                        self.alphaValue = 1
                        self.isFadingOut = false
                        completion()
                    }
                }
            }
        }
        if delay > 0, !reduce {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    fade()
                }
            }
        } else {
            fade()
        }
    }
}
