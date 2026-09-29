import AppKit
import Foundation
import QuartzCore

enum CaptureHighlight {
    /// Long enough for the angular glow to read, still under 1.5s.
    static let duration: TimeInterval = 1.0
    /// Opacity-only edge fade. No scale, inset, or path shrink on dismiss.
    static let edgeFadeDuration: TimeInterval = 0.18
    static let dismissesWithOpacityOnly = true
    static let dismissesWithScaleOrInset = false

    /// ScreenCaptureKit / CG frames use top-left origin at the main display.
    /// NSPanel uses AppKit bottom-left screen coordinates.
    enum CoordinateSpace: Equatable, Sendable {
        case appKit
        case captureQuartz
    }

    nonisolated static func shouldShow(frame: CGRect?) -> Bool {
        guard let frame else { return false }
        return frame.width > 1 && frame.height > 1
    }

    /// Glow every screenshot send. Not once-per-session.
    nonisolated static func shouldFlashOnSend(hasJPEG: Bool) -> Bool {
        hasJPEG
    }

    /// Convert a ScreenCaptureKit / CG top-left rect into AppKit screen coordinates.
    nonisolated static func appKitRect(fromQuartz rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: mainDisplayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Padded panel frame around an AppKit-space target. Stroke inset equals padding on every side.
    nonisolated static func panelFrame(capturing target: CGRect, padding: CGFloat) -> CGRect {
        target.insetBy(dx: -padding, dy: -padding)
    }

    @MainActor
    static func mainDisplayHeight() -> CGFloat {
        let mainID = CGMainDisplayID()
        if let screen = NSScreen.screens.first(where: { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == mainID
        }) {
            return screen.frame.height
        }
        return NSScreen.main?.frame.height ?? 0
    }

    @MainActor
    static func appKitTarget(
        frame: CGRect,
        space: CoordinateSpace
    ) -> CGRect {
        switch space {
        case .appKit:
            return frame
        case .captureQuartz:
            return appKitRect(fromQuartz: frame, mainDisplayHeight: mainDisplayHeight())
        }
    }

    /// Brief nonactivating Intelligence-style glow around the captured window or screen.
    /// Does not activate the app. Appears and dismisses with opacity only on the edge.
    @MainActor
    static func flash(
        frame: CGRect?,
        cornerRadius: CGFloat = IntelligenceGlowPolicy.windowCornerRadius,
        context: IntelligenceGlowContext = .capture,
        space: CoordinateSpace = .captureQuartz
    ) {
        guard shouldShow(frame: frame), let frame else { return }
        let settings = DebugPreviewStore.shared
        settings.activate(context, notify: false)
        let spec = settings.resolvedSpec(for: context)
        let variation = settings.variation(for: context)
        let pad = max(spec.padding, 4)
        let target = appKitTarget(frame: frame, space: space)
        let contentFrame = panelFrame(capturing: target, padding: pad)
        let panel = HighlightPanel(
            contentFrame: contentFrame,
            contentCornerRadius: cornerRadius,
            inset: pad,
            variation: variation,
            spec: spec
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = edgeFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        let hold = max(0, duration - edgeFadeDuration * 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + edgeFadeDuration + hold) { [weak panel] in
            MainActor.assumeIsolated {
                guard let panel, panel !== GlowPanelStore.persistent else { return }
                dismissOpacityOnly(panel)
            }
        }
    }

    /// Opacity-only dismiss. Keeps the stroke on the capture edge; no scale or inset.
    @MainActor
    private static func dismissOpacityOnly(_ panel: HighlightPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = edgeFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard panel !== GlowPanelStore.persistent else { return }
                panel.orderOut(nil)
                panel.close()
            }
        })
    }

    /// Persistent whole-card glow while dictating. Tracks an updated frame via `updatePersistent`.
    @MainActor
    static func showPersistent(
        frame: CGRect?,
        cornerRadius: CGFloat,
        context: IntelligenceGlowContext = .listening
    ) {
        guard shouldShow(frame: frame), let frame else {
            hidePersistent()
            return
        }
        let settings = DebugPreviewStore.shared
        settings.activate(context, notify: false)
        let spec = settings.resolvedSpec(for: context)
        let variation = settings.variation(for: context)
        let pad = max(spec.padding, 4)
        // Dictation uses the HUD plate frame already in AppKit space.
        let contentFrame = panelFrame(capturing: frame, padding: pad)
        if let existing = GlowPanelStore.persistent {
            existing.relayout(
                contentFrame: contentFrame,
                contentCornerRadius: cornerRadius,
                inset: pad,
                variation: variation,
                spec: spec
            )
            existing.alphaValue = 1
            existing.orderFrontRegardless()
            return
        }
        let panel = HighlightPanel(
            contentFrame: contentFrame,
            contentCornerRadius: cornerRadius,
            inset: pad,
            variation: variation,
            spec: spec
        )
        GlowPanelStore.persistent = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = edgeFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    @MainActor
    static func updatePersistent(
        frame: CGRect?,
        cornerRadius: CGFloat,
        context: IntelligenceGlowContext = .listening
    ) {
        guard GlowPanelStore.persistent != nil else { return }
        showPersistent(frame: frame, cornerRadius: cornerRadius, context: context)
    }

    @MainActor
    static func hidePersistent() {
        guard let panel = GlowPanelStore.persistent else { return }
        GlowPanelStore.persistent = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = edgeFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.close()
            }
        })
    }

    @MainActor
    static func refreshPersistentIfNeeded(
        frame: CGRect?,
        cornerRadius: CGFloat,
        context: IntelligenceGlowContext = .listening
    ) {
        guard GlowPanelStore.persistent != nil else { return }
        showPersistent(frame: frame, cornerRadius: cornerRadius, context: context)
    }
}

@MainActor
private enum GlowPanelStore {
    static var persistent: HighlightPanel?
}

@MainActor
private final class HighlightPanel: NSPanel {
    private let glowView: IntelligenceGlowCAView

    init(
        contentFrame: CGRect,
        contentCornerRadius: CGFloat,
        inset: CGFloat,
        variation: IntelligenceGlowVariation,
        spec: IntelligenceGlowSpec
    ) {
        glowView = IntelligenceGlowCAView(frame: NSRect(origin: .zero, size: contentFrame.size))
        super.init(
            contentRect: contentFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        // AppKit's default window close can look like a shrink. Opacity fade is explicit.
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = glowView
        glowView.apply(
            cornerRadius: contentCornerRadius,
            inset: inset,
            variation: variation,
            spec: spec
        )
    }

    func relayout(
        contentFrame: CGRect,
        contentCornerRadius: CGFloat,
        inset: CGFloat,
        variation: IntelligenceGlowVariation,
        spec: IntelligenceGlowSpec
    ) {
        setFrame(contentFrame, display: true)
        glowView.frame = NSRect(origin: .zero, size: contentFrame.size)
        glowView.apply(
            cornerRadius: contentCornerRadius,
            inset: inset,
            variation: variation,
            spec: spec
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// AppKit renderer for IntelligenceGlow variations on transparent overlay panels.
private final class IntelligenceGlowCAView: NSView {
    private let colors: [CGColor] = [
        NSColor(red: 188 / 255, green: 130 / 255, blue: 243 / 255, alpha: 1).cgColor,
        NSColor(red: 245 / 255, green: 185 / 255, blue: 234 / 255, alpha: 1).cgColor,
        NSColor(red: 141 / 255, green: 159 / 255, blue: 255 / 255, alpha: 1).cgColor,
        NSColor(red: 255 / 255, green: 103 / 255, blue: 120 / 255, alpha: 1).cgColor,
        NSColor(red: 255 / 255, green: 186 / 255, blue: 113 / 255, alpha: 1).cgColor,
        NSColor(red: 198 / 255, green: 134 / 255, blue: 255 / 255, alpha: 1).cgColor
    ]

    private var cornerRadius: CGFloat = 14
    private var inset: CGFloat = 14
    private var variation: IntelligenceGlowVariation = .overlay
    private var spec: IntelligenceGlowSpec = .resolved(from: .listening)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        cornerRadius: CGFloat,
        inset: CGFloat,
        variation: IntelligenceGlowVariation,
        spec: IntelligenceGlowSpec
    ) {
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.variation = variation
        self.spec = spec
        rebuildLayers()
    }

    override func layout() {
        super.layout()
        rebuildLayers()
    }

    private func rebuildLayers() {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        // Disable implicit bounds/transform animations that read as an inward collapse.
        root.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
            "path": NSNull(),
            "opacity": NSNull()
        ]
        root.opacity = Float(min(max(spec.opacity, 0), 1))
        root.transform = CATransform3DIdentity

        let bounds = root.bounds.insetBy(dx: inset, dy: inset)
        guard bounds.width > 2, bounds.height > 2 else { return }

        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let speed = max(spec.animationSpeed, 0.15)

        if variation.usesGlow {
            addGlowLayers(root: root, path: path, reduceMotion: reduceMotion, speed: speed)
        }
        if variation.usesSweep {
            addSweepLayer(root: root, path: path, bounds: bounds, reduceMotion: reduceMotion, speed: speed)
        }
    }

    private func addGlowLayers(
        root: CALayer,
        path: CGPath,
        reduceMotion: Bool,
        speed: Double
    ) {
        let count = min(spec.lineWidths.count, spec.blurs.count, spec.animationDurations.count)
        guard count > 0 else { return }
        let opacities: [Float] = [1, 0.9, 0.6, 0.4]

        for index in 0..<count {
            let lineWidth = spec.lineWidths[index]
            let blur = spec.blurs[index]
            let container = CALayer()
            container.frame = root.bounds
            container.opacity = opacities[min(index, opacities.count - 1)]

            let mask = CAShapeLayer()
            mask.fillColor = nil
            mask.strokeColor = NSColor.white.cgColor
            mask.lineWidth = max(lineWidth, 0.5)
            mask.path = path
            mask.frame = root.bounds
            container.mask = mask

            let gradient = CAGradientLayer()
            gradient.type = .conic
            gradient.colors = colors + [colors[0]]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            let overscan = max(root.bounds.width, root.bounds.height)
            gradient.frame = CGRect(
                x: (root.bounds.width - overscan * 1.5) / 2,
                y: (root.bounds.height - overscan * 1.5) / 2,
                width: overscan * 1.5,
                height: overscan * 1.5
            )
            container.addSublayer(gradient)

            if blur > 0 {
                container.shadowColor = colors[index % colors.count]
                container.shadowRadius = blur
                container.shadowOpacity = 1
                container.shadowOffset = .zero
                container.shadowPath = path
            }

            if !reduceMotion {
                // Rotate color only. Never scale or translate the stroke path.
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = Double.pi * 2
                spin.duration = (1.1 + Double(index) * 0.2) / speed
                spin.repeatCount = .infinity
                spin.isRemovedOnCompletion = false
                spin.timingFunction = CAMediaTimingFunction(name: .linear)
                gradient.add(spin, forKey: "spin")
            }

            // Keep stroke geometry fixed; only the gradient may spin.
            container.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "transform": NSNull(),
                "opacity": NSNull(),
                "shadowPath": NSNull(),
                "shadowRadius": NSNull()
            ]
            mask.actions = [
                "path": NSNull(),
                "lineWidth": NSNull(),
                "bounds": NSNull(),
                "position": NSNull()
            ]

            root.addSublayer(container)
        }
    }

    private func addSweepLayer(
        root: CALayer,
        path: CGPath,
        bounds: CGRect,
        reduceMotion: Bool,
        speed: Double
    ) {
        let base = CAShapeLayer()
        base.fillColor = nil
        base.strokeColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        base.lineWidth = max(spec.sweepLineWidth, 0.35)
        base.path = path
        base.frame = root.bounds
        root.addSublayer(base)

        let container = CALayer()
        container.frame = root.bounds

        let mask = CAShapeLayer()
        mask.fillColor = nil
        mask.strokeColor = NSColor.white.cgColor
        mask.lineWidth = max(spec.sweepLineWidth * 3, 1)
        mask.path = path
        mask.frame = root.bounds
        container.mask = mask

        let gradient = CAGradientLayer()
        gradient.type = .conic
        // Clear outside the sweep wedge, bright inside.
        let span = max(min(spec.sweepSpan, 359), 8) / 360.0
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 198 / 255, green: 134 / 255, blue: 255 / 255, alpha: 1).cgColor,
            NSColor(red: 255 / 255, green: 186 / 255, blue: 113 / 255, alpha: 1).cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor
        ]
        gradient.locations = [
            0,
            NSNumber(value: max(0, (spec.sweepOffset / 360).truncatingRemainder(dividingBy: 1))),
            NSNumber(value: min(1, span)),
            NSNumber(value: min(1, span + 0.08)),
            1
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        let overscan = max(root.bounds.width, root.bounds.height)
        gradient.frame = CGRect(
            x: (root.bounds.width - overscan * 1.5) / 2,
            y: (root.bounds.height - overscan * 1.5) / 2,
            width: overscan * 1.5,
            height: overscan * 1.5
        )
        container.addSublayer(gradient)

        let blur = max(spec.blurRadius * 0.15, 2)
        container.shadowColor = colors[0]
        container.shadowRadius = blur
        container.shadowOpacity = 0.9
        container.shadowOffset = .zero
        container.shadowPath = path

        if !reduceMotion {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 2.6 / speed
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            gradient.add(spin, forKey: "sweep")
        }

        root.addSublayer(container)
    }
}
