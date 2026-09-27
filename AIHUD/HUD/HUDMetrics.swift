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
    static let settingsSize = CGSize(width: 720, height: 480)
    static let debugSize = CGSize(width: 400, height: 640)
}
