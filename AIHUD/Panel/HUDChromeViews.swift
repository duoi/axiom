import AppKit
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

final class HUDChromeWrapper: NSView {
    var plate: NSView?
    var lip: NSView?
    var hasLip = false
    var cardHeight: CGFloat = HUDMetrics.minCardHeight

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
        super.layout()
        let width = bounds.width
        let card = max(HUDMetrics.minCardHeight, min(cardHeight, bounds.height))
        let plateY = hasLip ? HUDLayout.lipVisible : 0
        lip?.isHidden = !hasLip
        lip?.frame = HUDLayout.lipFrame(cardWidth: width)
        if hasLip {
            layer?.cornerRadius = 0
            layer?.masksToBounds = false
        } else {
            layer?.mask = nil
            layer?.cornerRadius = HUDMetrics.cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }
        plate?.frame = NSRect(x: 0, y: plateY, width: width, height: card)
        (plate as? CardGlassView)?.includeNarrowLip = hasLip
        (plate as? CardGlassView)?.containKeyFringe()
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

/// Keeps the window frame from painting a square behind the rounded plate.
final class CardGlassView: NSGlassEffectView {
    var includeNarrowLip = false
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        containKeyFringe()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
        containKeyFringe()
    }

    func containKeyFringe() {
        applyClearRoundedMask(to: self)
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
        if includeNarrowLip, view !== self {
            HUDLayout.applyLipWindowMask(to: view, hasLip: true)
            return
        }
        view.layer?.mask = nil
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
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
        subviews.forEach { $0.frame = bounds }
    }
}
