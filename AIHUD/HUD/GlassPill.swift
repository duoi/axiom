import SwiftUI

/// Groups the HUD toolbar the way `ToolbarSpacer` splits a system bar:
/// a leading cluster, a flexible gap, then the trailing hint and mic.
struct HUDToolbarCluster<Leading: View, Trailing: View>: View {
    var leading: Leading
    var trailing: Trailing

    init(
        @ViewBuilder _ leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GlassEffectContainer(spacing: HUDMaterial.glassContainerSpacing) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: HUDMetrics.controlSpacing) {
                    leading
                }
                Spacer(minLength: HUDMetrics.controlSpacing)
                HStack(spacing: HUDMetrics.controlSpacing) {
                    trailing
                }
            }
        }
    }
}

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
