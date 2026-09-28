import AppKit
import KeyboardShortcuts
import SwiftUI

struct HUDView: View {
    @Bindable var model: HUDModel
    var store: EndpointStore
    @State private var promptHeight = HUDMetrics.rowHeight

    var body: some View {
        let override = model.logoOverride
        VStack(alignment: .leading, spacing: 0) {
            promptRow(idleSlot: HUDModelMenu.idleSlot(
                dictating: model.dictating,
                override: override,
                endpoint: store.selectedEndpoint ?? ChatEndpointCatalog.onDeviceEndpoint
            ))
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
                settingsLine(voice, action: model.openVoiceSettings)
            }
            if model.session.showsAnswer || model.historyExpanded {
                history
            }
            toolbar
        }
        .frame(width: HUDMetrics.cardWidth)
        .frame(minHeight: HUDLayout.cardHeight(hasErrorLine: showsErrorLine), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius, style: .continuous))
        .background(Color.clear)
    }

    private func promptRow(idleSlot: HUDIdleSlot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                switch idleSlot {
                case .waveform:
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.orange)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                case .logo(let kind):
                    ProviderLogo(kind: kind, template: HUDIdleMark.usesTemplate)
                        .id(kind)
                        .foregroundStyle(
                            Color(
                                red: HUDIdleMark.red,
                                green: HUDIdleMark.green,
                                blue: HUDIdleMark.blue
                            )
                        )
                        .overlay {
                            ModelMenuHitView { view in
                                popModelMenu(from: view)
                            }
                        }
                        .help("Change model")
                        .accessibilityLabel("Change model")
                }
            }
            .id(model.logoOverride)
            .frame(width: 18, height: 18)
            PromptField(
                text: Binding(
                    get: { model.session.draft },
                    set: { model.setDraft($0) }
                ),
                placeholder: model.dictating && model.session.draft.isEmpty ? "Listening..." : "Ask anything...",
                multiline: model.displayedMultiline,
                onSubmit: { model.submit() },
                onReady: { model.promptEditor = $0 },
                onHeight: { height in
                    let line = PromptLayout.lineHeight(for: PromptLayout.font())
                    let extra = max(0, height - HUDMetrics.rowHeight)
                    let lines = model.displayedMultiline
                        ? min(PromptLayout.maxVisibleLines, 1 + Int((extra / max(line, 1)).rounded()))
                        : 1
                    let heightChanged = promptHeight != height
                    let linesChanged = model.promptLineCount != lines
                    promptHeight = height
                    model.promptLineCount = lines
                    if heightChanged || linesChanged {
                        model.onLayout()
                    }
                }
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
        .frame(height: model.displayedMultiline ? promptHeight : HUDMetrics.rowHeight)
        .padding(.horizontal, HUDMetrics.inset)
        .onChange(of: model.displayedMultiline) {
            if !model.displayedMultiline {
                promptHeight = HUDMetrics.rowHeight
                model.promptLineCount = 1
            }
            model.onLayout()
        }
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

    private var showsErrorLine: Bool {
        if store.blockingMessage != nil, model.session.phase == .composing {
            return true
        }
        if case .failed = model.session.phase {
            return true
        }
        if model.screenNotice != nil {
            return true
        }
        if let voice = model.voiceStatus, !voice.isEmpty {
            return true
        }
        return false
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
        .frame(height: HUDLayout.errorLineHeight, alignment: .leading)
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
                Text(ReplyMarkdown.attributed(model.session.displayAnswer))
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
                Text(ReplyMarkdown.attributed(row.text))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var toolbar: some View {
        HUDToolbarCluster {
            presetToggle
            captureControl
            Button(action: model.addContext) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text("Add context")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } trailing: {
            shortcutBadge
            micButton
        }
        .frame(height: HUDMetrics.rowHeight)
        .clipped()
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .hudCapsule(highlighted: model.session.preset == .agent)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func togglePreset() {
        model.setPreset(model.session.preset == .agent ? .ask : .agent)
    }

    private var captureControl: some View {
        let tint = model.captureArmed ? Color.primary : Color.secondary
        return ZStack {
            ForEach(CaptureTarget.allCases) { target in
                HStack(spacing: 6) {
                    Image(systemName: target.symbolName)
                    Text(target.title)
                    toolbarChevron
                }
            }
            .hidden()
        }
        .overlay {
            HStack(spacing: 0) {
                Button(action: model.toggleCapture) {
                    HStack(spacing: 6) {
                        Image(systemName: model.displayedCaptureTarget.symbolName)
                        Text(model.displayedCaptureTarget.title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                Button(action: popCaptureMenu) {
                    toolbarChevron
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(tint)
        .hudCapsule(highlighted: model.captureArmed)
        .fixedSize()
    }

    private var toolbarChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
    }

    private func popModelMenu(from view: NSView) {
        let proxy = ModelMenuProxy { providerID, modelID in
            model.selectChat(providerID: providerID, modelID: modelID)
        }
        let menu = NSMenu()
        let currentID = store.defaultEndpointID
        let currentModel = store.chatModelID
        for item in HUDModelMenu.items(
            endpoints: store.endpoints,
            chatID: currentID,
            chatModelID: currentModel,
            secret: { store.apiKey(for: $0) },
            onDeviceReady: OnDeviceChat.availability == .available
        ) {
            let row = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            row.state = item.providerID == currentID ? .on : .off
            let enabled = item.models.filter(\.enabled)
            if enabled.count == 1, let only = enabled.first {
                row.target = proxy
                row.action = #selector(ModelMenuProxy.pick(_:))
                row.representedObject = ModelMenuChoice(providerID: item.providerID, modelID: only.id)
            } else {
                let submenu = NSMenu()
                for model in item.models {
                    let modelItem = NSMenuItem(
                        title: model.title,
                        action: model.enabled ? #selector(ModelMenuProxy.pick(_:)) : nil,
                        keyEquivalent: ""
                    )
                    modelItem.isEnabled = model.enabled
                    if model.enabled {
                        modelItem.target = proxy
                        modelItem.representedObject = ModelMenuChoice(
                            providerID: item.providerID,
                            modelID: model.id
                        )
                    }
                    if item.providerID == currentID, model.enabled, model.id == currentModel {
                        modelItem.state = .on
                    }
                    submenu.addItem(modelItem)
                }
                row.submenu = submenu
            }
            menu.addItem(row)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
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
            item.state = target == model.displayedCaptureTarget ? .on : .off
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

private struct ModelMenuHitView: NSViewRepresentable {
    var action: (NSView) -> Void

    func makeNSView(context: Context) -> HitView {
        let view = HitView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: HitView, context: Context) {
        nsView.action = action
    }

    final class HitView: NSView {
        var action: ((NSView) -> Void)?

        override func mouseDown(with event: NSEvent) {
            action?(self)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

private final class ModelMenuChoice: NSObject {
    let providerID: UUID
    let modelID: String

    init(providerID: UUID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

@MainActor
private final class ModelMenuProxy: NSObject {
    let handler: (UUID, String) -> Void

    init(_ handler: @escaping (UUID, String) -> Void) {
        self.handler = handler
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModelMenuChoice else { return }
        handler(choice.providerID, choice.modelID)
    }
}

struct ProviderLogo: View {
    var kind: ProviderLogoKind
    var template: Bool = false

    var body: some View {
        Group {
            if let symbol = kind.systemSymbolName {
                Image(systemName: symbol)
                    .renderingMode(template ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
            } else {
                Image(kind.imageName)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(template ? .template : .original)
                    .scaledToFit()
            }
        }
        .accessibilityLabel(kind.accessibilityName)
        .id(kind.systemSymbolName ?? kind.imageName)
    }
}

struct AxiomLogo: View {
    var template: Bool = false

    var body: some View {
        ProviderLogo(kind: .axiom, template: template)
    }
}
