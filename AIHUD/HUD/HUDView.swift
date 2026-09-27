import KeyboardShortcuts
import SwiftUI

struct HUDView: View {
    @Bindable var model: HUDModel
    var store: EndpointStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            promptRow
            if !model.session.chips.isEmpty {
                chipRow
            }
            hairline
            if let message = store.blockingMessage, model.session.phase == .composing {
                settingsLine(message)
            } else if case .failed(let message) = model.session.phase {
                settingsLine(message)
            }
            if model.session.showsAnswer {
                answer
            }
            toolbar
        }
        .frame(width: 560)
        .frame(minHeight: 108, alignment: .top)
        .background(Color.clear)
    }

    private var promptRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            PromptField(
                text: Binding(
                    get: { model.session.draft },
                    set: { model.setDraft($0) }
                ),
                placeholder: "Ask anything...",
                onSubmit: { model.submit() },
                onReady: { model.textField = $0 }
            )
            Button(action: model.submitOrStop) {
                Image(systemName: model.session.showsStop ? "stop.fill" : "arrow.up.right")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(model.session.canSend || model.session.showsStop ? 0.9 : 0.35)
            .disabled(!model.session.canSend && !model.session.showsStop)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.session.chips) { chip in
                    HStack(spacing: 4) {
                        Text(chip.name)
                            .lineLimit(1)
                        Button {
                            model.removeChip(chip.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func settingsLine(_ message: String) -> some View {
        Button(action: model.openSettings) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var answer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if model.session.phase == .waiting {
                        Text("Thinking…")
                            .foregroundStyle(.secondary)
                    }
                    if !model.session.displayAnswer.isEmpty {
                        Text(model.session.displayAnswer)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("answer-end")
                }
                .font(.body)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 320)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                if geometry.contentSize.height <= geometry.containerSize.height + 1 {
                    return true
                }
                let leftover = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                return leftover < 24
            } action: { _, atBottom in
                model.stickToBottom = atBottom
            }
            .onChange(of: model.session.displayAnswer) {
                guard model.stickToBottom else { return }
                proxy.scrollTo("answer-end", anchor: .bottom)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Ask") { model.setPreset(.ask) }
                Button {
                    model.setPreset(.agent)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agent")
                        Text("Writes plans and steps. No tools in this version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.session.preset.symbolName)
                    Text(model.session.preset.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button(action: model.addContext) {
                HStack(spacing: 5) {
                    Image(systemName: "paperclip")
                    Text("Add context")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
            shortcutBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shortcutBadge: some View {
        Text(shortcutLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            )
    }

    private var shortcutLabel: String {
        guard let shortcut = KeyboardShortcuts.Shortcut(name: .toggleHUD) else {
            return "⌃⌥K"
        }
        return shortcut.description
    }
}
