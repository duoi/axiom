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
        plate?.layoutSubtreeIfNeeded()
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
    var includeNarrowLip = false
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
        if content.frame != parent.bounds {
            content.frame = parent.bounds
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
        for child in subviews {
            if child.frame != bounds {
                child.frame = bounds
            }
            child.layoutSubtreeIfNeeded()
        }
    }
}
