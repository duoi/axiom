import AppKit
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
            if let notice = model.screenNotice {
                settingsLine(notice, action: model.openScreenSettings)
            }
            if let voice = model.voiceStatus, !voice.isEmpty {
                settingsLine(voice, action: model.openSettings)
            }
            if model.session.showsAnswer || model.historyExpanded {
                history
            }
            toolbar
        }
        .frame(width: HUDMetrics.cardWidth)
        .frame(minHeight: HUDMetrics.minCardHeight, alignment: .top)
        .background(Color.clear)
    }

    private var promptRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if model.dictating {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.orange)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                } else {
                    AxiomLogo(template: true)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            PromptField(
                text: Binding(
                    get: { model.session.draft },
                    set: { model.setDraft($0) }
                ),
                placeholder: model.dictating && model.session.draft.isEmpty ? "Listening..." : "Ask anything...",
                onSubmit: { model.submit() },
                onReady: { model.textField = $0 }
            )
            Button(action: model.submitOrStop) {
                Image(systemName: model.session.showsStop ? "stop.fill" : "arrow.up.right")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(model.session.canSend || model.captureArmed || model.session.showsStop ? 0.9 : 0.35)
            .disabled(!model.session.canSend && !model.captureArmed && !model.session.showsStop)
        }
        .frame(height: HUDMetrics.rowHeight)
        .padding(.horizontal, HUDMetrics.inset)
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
            .padding(.horizontal, HUDMetrics.inset)
            .padding(.bottom, 8)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, HUDMetrics.inset)
    }

    private func settingsLine(_ message: String, action: (() -> Void)? = nil) -> some View {
        Button(action: action ?? model.openSettings) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HUDMetrics.inset)
        .padding(.top, 10)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.historyExpanded {
                expandedTranscript
            } else {
                compactAnswer
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.session.turns.contains(where: { $0.role == .user }) {
                Button(action: model.toggleHistory) {
                    Image(systemName: model.historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
    }

    private var compactAnswer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.session.phase == .waiting, model.session.displayAnswer.isEmpty {
                Text("Thinking…")
                    .foregroundStyle(.secondary)
            }
            if !model.session.displayAnswer.isEmpty {
                Text(model.session.displayAnswer)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.body)
        .padding(.horizontal, HUDMetrics.inset)
        .padding(.vertical, 12)
        .padding(.trailing, 18)
    }

    private var expandedTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let started = model.session.startedAt {
                        Text(started.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(Transcript.rows(in: model.session, expanded: true).enumerated()), id: \.offset) { _, row in
                        transcriptRow(row)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("answer-end")
                }
                .padding(.horizontal, HUDMetrics.inset)
                .padding(.vertical, 12)
                .padding(.trailing, 18)
            }
            .frame(maxHeight: 480)
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

    @ViewBuilder
    private func transcriptRow(_ row: TranscriptRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.kind == .user {
                Text(row.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(row.chipNames, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if row.live, row.text.isEmpty {
                Text("Thinking…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(markup(row.text))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func markup(_ source: String) -> AttributedString {
        var result = AttributedString()
        for run in LightMarkup.parse(source) {
            switch run {
            case .plain(let text):
                result += AttributedString(text)
            case .bold(let text):
                var piece = AttributedString(text)
                piece.font = .body.bold()
                result += piece
            case .bullet(let text):
                if !result.characters.isEmpty {
                    result += AttributedString("\n")
                }
                result += AttributedString("• \(text)")
            case .numbered(let number, let text):
                if !result.characters.isEmpty {
                    result += AttributedString("\n")
                }
                result += AttributedString("\(number). \(text)")
            }
        }
        return result
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: HUDMetrics.controlSpacing) {
            presetToggle
            captureControl
            micButton
            Button(action: model.addContext) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text("Add context")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer(minLength: HUDMetrics.controlSpacing)
            shortcutBadge
        }
        .frame(height: HUDMetrics.rowHeight)
        .padding(.horizontal, HUDMetrics.inset)
    }

    private var micButton: some View {
        Button(action: model.toggleDictation) {
            Image(systemName: model.dictating ? "waveform" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.dictating ? Color.orange : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: model.dictating)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(model.dictating ? "Stop dictation" : "Dictate")
    }

    private var pillMatte: Bool { model.pillIsMatte }

    private var presetToggle: some View {
        Button(action: togglePreset) {
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Image(systemName: Preset.agent.symbolName)
                    Text(Preset.agent.title)
                }
                .hidden()
                HStack(spacing: 6) {
                    Image(systemName: model.session.preset.symbolName)
                    Text(model.session.preset.title)
                }
            }
            .padding(HUDMetrics.pillInset)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .background {
                if model.session.preset == .agent {
                    GlassBackdrop(matte: pillMatte, amount: model.store.glassAmount)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func togglePreset() {
        model.setPreset(model.session.preset == .agent ? .ask : .agent)
    }

    private var captureControl: some View {
        let tint = model.captureArmed ? Color.primary : Color.secondary
        return HStack(spacing: 6) {
            Button(action: model.toggleCapture) {
                HStack(spacing: 6) {
                    Image(systemName: model.store.captureTarget.symbolName)
                    Text(model.store.captureTarget.title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: popCaptureMenu) {
                toolbarChevron
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(HUDMetrics.pillInset)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(tint)
        .background {
            if model.captureArmed {
                GlassBackdrop(matte: pillMatte, amount: model.store.glassAmount)
            }
        }
        .fixedSize()
    }

    private var toolbarChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
    }

    private func popCaptureMenu() {
        let proxy = CaptureMenuProxy { model.setCaptureTarget($0) }
        let menu = NSMenu()
        for target in CaptureTarget.allCases {
            let item = NSMenuItem(
                title: target.title,
                action: #selector(CaptureMenuProxy.pick(_:)),
                keyEquivalent: ""
            )
            item.target = proxy
            item.representedObject = target.rawValue
            item.state = target == model.store.captureTarget ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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

@MainActor
private final class CaptureMenuProxy: NSObject {
    let handler: (CaptureTarget) -> Void

    init(_ handler: @escaping (CaptureTarget) -> Void) {
        self.handler = handler
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let target = CaptureTarget(rawValue: raw)
        else { return }
        handler(target)
    }
}

struct AxiomLogo: View {
    var template: Bool = false

    var body: some View {
        Image("AxiomLogo")
            .resizable()
            .interpolation(.high)
            .renderingMode(template ? .template : .original)
            .scaledToFit()
            .accessibilityLabel("Axiom")
    }
}
