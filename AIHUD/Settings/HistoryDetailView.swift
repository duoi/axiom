import AppKit
import SwiftUI

struct HistoryDetailView: View {
    let entry: HistoryEntry
    let store: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? "Conversation" : entry.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(HUDMetrics.inset)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                    ForEach(Array(entry.turns.enumerated()), id: \.offset) { _, turn in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turn.role == "user" ? "You" : "Axiom")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !turn.text.isEmpty {
                                Text(turn.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(turn.screenshotNames, id: \.self) { name in
                                if let data = store.loadScreenshot(named: name, for: entry.id),
                                   let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 480)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal, HUDMetrics.inset)
                    }
                }
                .padding(.vertical, HUDMetrics.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
