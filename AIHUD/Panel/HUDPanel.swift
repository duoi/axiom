import AppKit

final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var menuTracking = false
    private var didPlace = false
    private let cardWidth: CGFloat = HUDMetrics.cardWidth

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
        if menuTracking { return }
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
        setFrame(NSRect(origin: origin, size: size), display: true)
        didPlace = true
        invalidateShadow()
    }

    func resizePinnedTop(to height: CGFloat, animated: Bool) {
        let next = HUDLayout.framePinnedTop(current: frame, height: height)
        guard next.height != frame.height else { return }
        if !didPlace {
            var placed = next
            placed.origin = frame.origin
            _ = animated
            setFrame(placed, display: true)
            invalidateShadow()
            return
        }
        _ = animated
        setFrame(next, display: true)
        invalidateShadow()
    }

    func reveal() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.15
            animator().alphaValue = 1
        }
    }

    func fadeOut(completion: @escaping @Sendable () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.12
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.orderOut(nil)
                    self?.alphaValue = 1
                    completion()
                }
            }
        }
    }
}
