import AppKit
import SwiftUI

struct DebugTranscriptView: View {
    @Bindable private var store = DebugTranscriptStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Raw chat HTTP. Secrets are replaced with [redacted].")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { store.clear() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                ScrollViewReader { proxy in
                    Text(store.text.isEmpty ? "Waiting for a chat send…" : store.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("tail")
                        .onChange(of: store.text) { _, _ in
                            proxy.scrollTo("tail", anchor: .bottom)
                        }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
