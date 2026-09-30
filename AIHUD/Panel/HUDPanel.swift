import AppKit

enum HUDEscape {
    static let keyCode: UInt16 = 53

    /// ESC dismisses whenever the panel is key. The first responder does not matter.
    static func shouldDismiss(
        keyCode: UInt16,
        panelIsKey: Bool,
        menuTracking: Bool,
        hasAttachedSheet: Bool,
        isComposing: Bool
    ) -> Bool {
        keyCode == Self.keyCode
            && panelIsKey
            && !menuTracking
            && !hasAttachedSheet
            && !isComposing
    }
}

enum HUDShortcut: Equatable {
    case cyclePreset
    case cycleCapture
    case addContext
    case toggleIncognito
    case toggleDictation
}

enum HUDShortcuts {
    /// Control chords while the card is key. Command, Option, and Shift stay with the field.
    static func action(
        characters: String?,
        control: Bool,
        command: Bool,
        option: Bool,
        shift: Bool,
        panelIsKey: Bool,
        menuTracking: Bool,
        hasAttachedSheet: Bool
    ) -> HUDShortcut? {
        guard panelIsKey, !menuTracking, !hasAttachedSheet, control, !command, !option, !shift else {
            return nil
        }
        switch characters?.lowercased() {
        case "a": return .cyclePreset
        case "s": return .cycleCapture
        case "c": return .addContext
        case "i": return .toggleIncognito
        case "'": return .toggleDictation
        default: return nil
        }
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

    /// Fade-out must not orderOut until the animation interval has elapsed.
    static func shouldOrderOut(elapsed: TimeInterval, duration: TimeInterval) -> Bool {
        elapsed >= duration
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
    private var fadeToken = 0
    private(set) var isFadingOut = false
    var onFrameStep: (() -> Void)?
    private var frameTimer: Timer?
    private var frameAnim: FrameAnim?

    private struct FrameAnim {
        var from: NSRect
        var to: NSRect
        var start: TimeInterval
        var duration: TimeInterval
    }

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
        guard HUDEscape.shouldDismiss(
            keyCode: event.keyCode,
            panelIsKey: isKeyWindow,
            menuTracking: menuTracking,
            hasAttachedSheet: attachedSheet != nil,
            isComposing: isComposingInput
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
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        cancelFrameAnimation()
        didPlace = false
        replyPinTopMaxY = nil
        setFrame(NSRect(origin: origin, size: size), display: true)
        didPlace = true
        invalidateShadow()
    }

    func resizePinnedTop(to height: CGFloat, animated: Bool) {
        resizeForReply(to: height, replyLines: 0, animated: animated)
    }

    func resizeForReply(
        to height: CGFloat,
        replyLines: Int,
        chromeHeight: CGFloat = HUDMetrics.minCardHeight,
        animated: Bool
    ) {
        let current = presentedFrame()
        if replyPinTopMaxY == nil {
            let extraUp = HUDLayout.replyExtraUpHeight(lines: replyLines)
            replyPinTopMaxY = current.maxY - extraUp
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
        if let anim = frameAnim, HUDFrameMotion.matches(anim.to, next) {
            return
        }
        if !didPlace {
            next.origin = frame.origin
            finishFrameAnimation(at: next)
            return
        }
        if HUDFrameMotion.matches(current, next) {
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
        frameAnim = FrameAnim(
            from: current,
            to: next,
            start: Date().timeIntervalSinceReferenceDate,
            duration: duration
        )
        if !HUDFrameMotion.matches(frame, current) {
            setFrame(current, display: false)
        }
        startFrameTimer()
    }

    /// Instant absence for a screen shot. No fade, and no AppKit window-close shrink.
    func concealForCapture() {
        cancelFrameAnimation()
        fadeToken += 1
        isFadingOut = false
        animationBehavior = .none
        alphaValue = 0
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        orderOut(nil)
        NSAnimationContext.endGrouping()
    }

    private func presentedFrame() -> NSRect {
        guard let anim = frameAnim else { return frame }
        let linear = (Date().timeIntervalSinceReferenceDate - anim.start) / anim.duration
        if linear >= 1 { return anim.to }
        return HUDFrameMotion.frame(from: anim.from, to: anim.to, linearProgress: linear)
    }

    private func finishFrameAnimation(at rect: NSRect) {
        cancelFrameAnimation()
        setFrame(rect, display: true)
        invalidateShadow()
    }

    private func cancelFrameAnimation() {
        frameAnim = nil
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
        guard let anim = frameAnim else {
            stopFrameTimer()
            return
        }
        let linear = (Date().timeIntervalSinceReferenceDate - anim.start) / anim.duration
        if linear >= 1 {
            frameAnim = nil
            setFrame(anim.to, display: false)
            invalidateShadow()
            stopFrameTimer()
            onFrameStep?()
            displayIfNeeded()
            return
        }
        let rect = HUDFrameMotion.frame(from: anim.from, to: anim.to, linearProgress: linear)
        setFrame(rect, display: false)
        onFrameStep?()
        displayIfNeeded()
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

    func fadeOut(completion: @escaping @Sendable () -> Void) {
        guard isVisible else {
            completion()
            return
        }
        fadeToken += 1
        let token = fadeToken
        isFadingOut = true
        let duration = HUDPanelFade.animationDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        // Drop key so ESC / typing do not stick on a vanishing card.
        resignKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.fadeToken == token else { return }
                    // Animation completion is the orderOut gate; policy is covered in tests.
                    self.orderOut(nil)
                    self.alphaValue = 1
                    self.isFadingOut = false
                    completion()
                }
            }
        }
    }
}
