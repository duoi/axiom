import CoreGraphics
import Foundation

enum HUDMaterial {
    static let amountKey = "hud.glassAmount"
    static let matteKey = "hud.usesMatte"
    static let styleKey = "hud.glassStyle"

    static func effectStyle(matte: Bool) -> GlassStyle {
        matte ? .regular : .clear
    }

    static func usesSolidCard(reduceTransparency: Bool) -> Bool {
        reduceTransparency
    }

    static func clampAmount(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Opacity of the window-color veil. 100% glass is clear.
    static func veilOpacity(glassAmount: Double) -> Double {
        let amount = clampAmount(glassAmount)
        return amount >= 0.99 ? 0 : 1 - amount
    }

    /// Zero batches similar descendant glass without merging shapes that only sit nearby.
    static var glassContainerSpacing: CGFloat { 0 }

    static func loadAmount(from defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: amountKey) != nil else { return 0.5 }
        return clampAmount(defaults.double(forKey: amountKey))
    }

    static func saveAmount(_ value: Double, to defaults: UserDefaults) {
        defaults.set(clampAmount(value), forKey: amountKey)
    }
}
