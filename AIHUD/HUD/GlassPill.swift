import SwiftUI

/// Quiet fill for an overlay that sits on the card plate. Not glass.
struct HUDSelectionFill: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
    }
}

extension View {
    /// Content-hugging capsule on the card plate. Not a system glass bezel.
    func hudCapsule(highlighted: Bool) -> some View {
        padding(HUDMetrics.pillInset)
            .background {
                if highlighted {
                    HUDSelectionFill()
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}
