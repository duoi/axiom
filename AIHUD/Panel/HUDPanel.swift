import AppKit

final class HUDPanel: NSPanel {
    var onCancel: (() -> Void)?
    var menuTracking = false
    private var didPlace = false
    private let cardWidth: CGFloat = 560

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 110),
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
        let size = NSSize(width: cardWidth, height: max(100, height))
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
        let nextHeight = max(100, height)
        guard abs(nextHeight - frame.height) > 0.5 else { return }
        var next = frame
        let delta = nextHeight - next.height
        next.size.width = cardWidth
        next.size.height = nextHeight
        if didPlace {
            next.origin.y -= delta
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(next, display: true)
            } completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.invalidateShadow()
                    }
                }
            }
        } else {
            setFrame(next, display: true)
            invalidateShadow()
        }
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
