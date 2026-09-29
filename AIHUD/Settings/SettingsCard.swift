import AppKit
import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
            content()
        }
        .padding(HUDMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
