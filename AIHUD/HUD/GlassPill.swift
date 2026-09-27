import AppKit
import SwiftUI

struct GlassBackdrop: NSViewRepresentable {
    var matte: Bool
    var amount: Double

    func makeNSView(context: Context) -> GlassBackdropView {
        let view = GlassBackdropView()
        view.apply(matte: matte, amount: amount)
        return view
    }

    func updateNSView(_ nsView: GlassBackdropView, context: Context) {
        nsView.apply(matte: matte, amount: amount)
    }
}

final class GlassBackdropView: NSView {
    private let glass = NSGlassEffectView()
    private var appliedMatte: Bool?
    private var appliedAmount: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        glass.cornerRadius = HUDMetrics.cornerRadius
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = false
        }
        addSubview(glass)
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }

    func apply(matte: Bool, amount: Double) {
        if appliedMatte == matte, appliedAmount == amount { return }
        appliedMatte = matte
        appliedAmount = amount
        let style = HUDMaterial.effectStyle(matte: matte)
        glass.style = style == .regular ? .regular : .clear
        glass.cornerRadius = HUDMetrics.cornerRadius
        let veil = HUDMaterial.veilOpacity(glassAmount: amount)
        glass.tintColor = veil == 0 ? nil : NSColor.windowBackgroundColor.withAlphaComponent(veil)
    }
}
