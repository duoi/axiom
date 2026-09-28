import AppKit
import CoreGraphics

struct HUDInsets: Equatable, Sendable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static func equal(_ value: CGFloat) -> HUDInsets {
        HUDInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

enum HUDMetrics {
    static let cardWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 24
    static let inset: CGFloat = 20
    static let pillInset: CGFloat = 8
    static var pillInsets: HUDInsets { .equal(pillInset) }
    static let rowHeight: CGFloat = 52
    static let controlSpacing: CGFloat = 20
    static let sidebarWidth: CGFloat = 184
    static let minCardHeight: CGFloat = 108
    static let settingsSize = CGSize(width: 900, height: 820)
    static let debugSize = CGSize(width: 440, height: 720)
}

enum HUDLayout {
    static let errorLineHeight: CGFloat = 28
    /// Ignore sub-point and 1pt fittingSize flicker so the panel does not step.
    static let heightFlicker: CGFloat = 1

    static func cardHeight(hasErrorLine: Bool) -> CGFloat {
        HUDMetrics.minCardHeight + (hasErrorLine ? errorLineHeight : 0)
    }

    static func settledHeight(
        proposed: CGFloat,
        previous: CGFloat,
        lineCount: Int,
        multiline: Bool
    ) -> CGFloat {
        let next = max(HUDMetrics.minCardHeight, proposed)
        let prior = max(HUDMetrics.minCardHeight, previous)
        let delta = next - prior
        if abs(delta) <= heightFlicker {
            return prior
        }
        let line = PromptLayout.lineHeight(for: PromptLayout.font())
        if multiline {
            let extra = max(0, lineCount - 1)
            if extra == 0, abs(delta) < line {
                return prior
            }
            if abs(delta) + heightFlicker >= line {
                return next
            }
            return prior
        }
        if abs(delta) < line {
            return prior
        }
        return next
    }

    static func framePinnedTop(current: NSRect, height: CGFloat) -> NSRect {
        let nextHeight = max(HUDMetrics.minCardHeight, height)
        var next = current
        next.size.width = HUDMetrics.cardWidth
        let delta = nextHeight - current.height
        next.size.height = nextHeight
        next.origin.y -= delta
        return next
    }
}
