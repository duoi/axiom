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

final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var menuTracking = false
    private var didPlace = false
    private var replyPinTopMaxY: CGFloat?
    private let cardWidth: CGFloat = HUDMetrics.cardWidth
    private var fadeToken = 0
    private(set) var isFadingOut = false

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
        if replyPinTopMaxY == nil {
            let extraUp = HUDLayout.replyExtraUpHeight(lines: replyLines)
            replyPinTopMaxY = frame.maxY - extraUp
        }
        let visible = screen?.visibleFrame
        var next = HUDLayout.frameForReplyGrowth(
            x: frame.origin.x,
            pinTopMaxY: replyPinTopMaxY ?? frame.maxY,
            height: height,
            replyLines: replyLines,
            chromeHeight: chromeHeight,
            visibleFrame: visible
        )
        guard next != frame else { return }
        if !didPlace {
            next.origin = frame.origin
            _ = animated
            setFrame(next, display: true)
            invalidateShadow()
            return
        }
        _ = animated
        setFrame(next, display: true)
        invalidateShadow()
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
