import AppKit
import KeyboardShortcuts
import SwiftUI

struct HUDView: View {
    @Bindable var model: HUDModel
    var store: EndpointStore
    /// Offscreen height probe. It must not take the live prompt editor or report line height.
    var measuresOnly = false
    @State private var promptHeight = HUDMetrics.rowHeight
    @State private var scrollerVisible = false
    @Bindable private var preview = DebugPreviewStore.shared

    var body: some View {
        let override = model.logoOverride
        VStack(alignment: .leading, spacing: 0) {
            promptRow(
                idleSlot: HUDModelMenu.idleSlot(
                    dictating: model.dictating,
                    override: override,
                    endpoint: store.selectedEndpoint ?? ChatEndpointCatalog.onDeviceEndpoint
                ),
                orbChoice: preview.cardOrb
            )
            if !model.session.chips.isEmpty {
                chipRow
            }
            hairline
            if HistoryChromePolicy.showsReplyRegion(
                answer: model.session.displayAnswer,
                phase: model.session.phase,
                historyExpanded: model.historyExpanded
            ) {
                history
            }
            toolbar
        }
        .padding(.bottom, HUDLayout.cardBottomSlack)
        .frame(width: HUDMetrics.cardWidth)
        .frame(minHeight: HUDLayout.cardHeight(), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
    }

    private func promptRow(
        idleSlot: HUDIdleSlot,
        orbChoice: ThinkingOrbChoice
    ) -> some View {
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
                isEditable: PromptInFlightPolicy.isEditable(phase: model.session.phase),
                showsInFlightShimmer: showsInFlightShimmer,
                onSubmit: { model.submit() },
                onReady: { editor in
                    guard !measuresOnly else { return }
                    model.promptEditor = editor
                },
                onHeight: { height in
                    guard !measuresOnly else { return }
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
                if ReplyWaitingChrome.showsComposingOrb(
                    phase: model.session.phase,
                    answer: model.session.displayAnswer
                ) {
                    AnimatedThinkingOrb(choice: orbChoice)
                } else {
                    Image(systemName: model.session.showsStop ? "stop.fill" : "arrow.up.right")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(model.session.canSend || model.captureArmed || model.session.showsStop ? 0.9 : 0.35)
            .disabled(!model.session.canSend && !model.captureArmed && !model.session.showsStop)
        }
        .frame(
            width: HUDLayout.rowWidth,
            height: model.displayedMultiline ? promptHeight : HUDMetrics.rowHeight
        )
        .padding(.horizontal, HUDMetrics.inset)
        .onChange(of: model.displayedMultiline) {
            if !model.displayedMultiline {
                promptHeight = HUDMetrics.rowHeight
                model.promptLineCount = 1
            }
            model.onLayout()
        }
    }

    private var showsInFlightShimmer: Bool {
        PromptInFlightPolicy.isInFlight(model.session.phase)
            && !model.session.draft.isEmpty
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

    private var history: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if model.historyExpanded {
                    middleScroll(
                        height: HUDLayout.replyBodyHeight(lines: HUDLayout.replyMaxLines),
                        tailID: "answer-end",
                        tracked: model.session.displayAnswer
                    ) {
                        expandedTranscriptContent
                    }
                } else {
                    compactAnswer
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if HistoryChromePolicy.showsExpandChevron(
                answer: model.session.displayAnswer,
                phase: model.session.phase,
                historyExpanded: model.historyExpanded,
                hasUserTurns: model.session.turns.contains(where: { $0.role == .user })
            ) {
                Button(action: model.toggleHistory) {
                    Image(systemName: model.historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, HUDMetrics.inset)
                .opacity(HUDLayout.expandChevronOpacity(scrollerVisible: scrollerVisible))
                .animation(
                    .easeInOut(duration: HUDLayout.scrollerFadeDuration),
                    value: scrollerVisible
                )
                .allowsHitTesting(!scrollerVisible)
                .accessibilityHidden(scrollerVisible)
            }
        }
    }

    private var compactAnswer: some View {
        let text = model.session.displayAnswer
        let lines = HUDLayout.wrappedReplyLines(text)
        let bodyHeight = HUDLayout.replyBodyHeight(lines: lines)
        let content = compactReplyText(text)
        return Group {
            if model.session.phase == .waiting, text.isEmpty {
                EmptyView()
            } else if lines > HUDLayout.replyMaxLines {
                middleScroll(height: bodyHeight, tailID: "reply-tail", tracked: text) {
                    content
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    content
                        .frame(height: bodyHeight, alignment: .top)
                }
                .padding(.leading, HUDMetrics.inset)
                .padding(.trailing, HUDMetrics.inset + HUDMetrics.controlSize)
                .padding(.vertical, 12)
                .onAppear { scrollerVisible = false }
            }
        }
        .font(Font(HUDLayout.replyFont))
    }

    private func compactReplyText(_ text: String) -> some View {
        Text(HUDLayout.styledReply(text))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func middleScroll<Content: View>(
        height: CGFloat,
        tailID: String,
        tracked: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ReplyScroll(
            height: height,
            tailID: tailID,
            tracked: tracked,
            stickToBottom: $model.stickToBottom,
            scrollerVisible: $scrollerVisible,
            content: content
        )
        .padding(.horizontal, HUDMetrics.inset)
        .padding(.vertical, 12)
    }

    private var expandedTranscriptContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let started = model.session.startedAt {
                Text(started.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(Transcript.rows(in: model.session, expanded: true).enumerated()), id: \.offset) { _, row in
                transcriptRow(row)
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
                EmptyView()
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
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: HUDMetrics.controlSpacing) {
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
            }
            Spacer(minLength: HUDMetrics.controlSpacing)
            HStack(spacing: HUDMetrics.controlSpacing) {
                if store.savesHistory {
                    historyGhostButton
                } else {
                    shortcutBadge
                }
                micButton
            }
        }
        .frame(width: HUDLayout.rowWidth, height: HUDMetrics.rowHeight)
        .clipped()
        .padding(.horizontal, HUDMetrics.inset)
    }

    private var micButton: some View {
        Button(action: model.toggleDictation) {
            Image(systemName: model.dictating ? "waveform" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.dictating ? Color.orange : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: model.dictating)
                .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
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
        let reasoningProxy = ReasoningMenuProxy { effort in
            store.reasoningEffort = effort
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
        menu.addItem(.separator())
        let reasoning = NSMenuItem(title: "Reasoning", action: nil, keyEquivalent: "")
        let reasoningMenu = NSMenu()
        for effort in ReasoningEffort.allCases {
            let item = NSMenuItem(
                title: effort.title,
                action: #selector(ReasoningMenuProxy.pick(_:)),
                keyEquivalent: ""
            )
            item.target = reasoningProxy
            item.representedObject = effort.rawValue
            item.state = effort == store.reasoningEffort ? .on : .off
            reasoningMenu.addItem(item)
        }
        reasoning.submenu = reasoningMenu
        menu.addItem(reasoning)
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

    private var historyGhostButton: some View {
        Button(action: model.toggleHistoryExclusion) {
            Image("Incognito")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(model.historyExcluded ? Color.primary : Color.secondary)
                .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.historyExcluded ? "Record this chat" : "Don't record this chat")
        .accessibilityLabel(model.historyExcluded ? "Recording off" : "Recording on")
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

private struct ReplyScroll<Content: View>: View {
    var height: CGFloat
    var tailID: String
    var tracked: String
    @Binding var stickToBottom: Bool
    @Binding var scrollerVisible: Bool
    @ViewBuilder var content: Content
    @State private var fade = HUDLayout.ScrollFadeEdges.none
    @State private var hideTask: Task<Void, Never>?
    @State private var didReachBottom = false

    var body: some View {
        ScrollViewReader { proxy in
            Color.clear
                .frame(height: height)
                .overlay {
                    ScrollView {
                        content
                            .background {
                                OverlayScrollerInstaller(active: scrollerVisible)
                            }
                        Color.clear
                            .frame(height: 1)
                            .id(tailID)
                    }
                    .scrollIndicators(.automatic)
                    .onScrollPhaseChange { _, phase in
                        let live: Bool
                        switch phase {
                        case .interacting, .tracking, .decelerating:
                            live = true
                        default:
                            live = false
                        }
                        if live {
                            hideTask?.cancel()
                            scrollerVisible = true
                        } else if scrollerVisible {
                            hideTask?.cancel()
                            hideTask = Task { @MainActor in
                                let delay = UInt64(HUDLayout.scrollerHideDelay * 1_000_000_000)
                                try? await Task.sleep(nanoseconds: delay)
                                guard !Task.isCancelled else { return }
                                scrollerVisible = false
                            }
                        }
                    }
                    .onDisappear {
                        hideTask?.cancel()
                        scrollerVisible = false
                    }
                    .mask {
                        fadeMask
                    }
                    .onScrollGeometryChange(for: HUDLayout.ScrollFadeEdges.self) { geometry in
                        HUDLayout.scrollFadeEdges(
                            offset: geometry.contentOffset.y,
                            contentHeight: geometry.contentSize.height,
                            viewport: geometry.containerSize.height
                        )
                    } action: { _, next in
                        fade = next
                    }
                    .onScrollGeometryChange(for: HUDLayout.ScrollPin.self) { geometry in
                        HUDLayout.scrollPin(
                            offset: geometry.contentOffset.y,
                            contentHeight: geometry.contentSize.height,
                            viewport: geometry.containerSize.height
                        )
                    } action: { _, next in
                        if next.fits {
                            return
                        }
                        if next.atBottom {
                            didReachBottom = true
                            stickToBottom = true
                        } else if didReachBottom {
                            stickToBottom = false
                        } else {
                            proxy.scrollTo(tailID, anchor: .bottom)
                        }
                    }
                    .onChange(of: tracked) {
                        guard stickToBottom else { return }
                        proxy.scrollTo(tailID, anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo(tailID, anchor: .bottom)
                    }
                }
                .clipShape(Rectangle())
        }
    }

    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fade.top ? HUDLayout.scrollFadeLength : 0)
            Rectangle()
                .fill(.black)
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fade.bottom ? HUDLayout.scrollFadeLength : 0)
        }
    }
}

private struct OverlayScrollerInstaller: NSViewRepresentable {
    var active: Bool

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.active = active
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.active = active
        nsView.install()
    }

    final class Probe: NSView {
        var active = false
        private var configured = false
        private var applied: Bool?
        private var fading = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            install()
        }

        override func layout() {
            super.layout()
            install()
        }

        func install() {
            guard let scroll = enclosingScrollView ?? nearestScrollView() else { return }
            if !configured {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.hasVerticalScroller = true
                scroll.hasHorizontalScroller = false
                scroll.horizontalScrollElasticity = .none
                configured = true
            }
            guard let scroller = scroll.verticalScroller else { return }
            scroller.isHidden = false
            let target: CGFloat = active ? 1 : 0
            if applied == nil {
                scroller.alphaValue = target
                applied = active
                return
            }
            if applied != active {
                applied = active
                fading = true
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = HUDLayout.scrollerFadeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scroller.animator().alphaValue = target
                }, completionHandler: { [weak self] in
                    self?.fading = false
                    scroller.alphaValue = target
                })
                return
            }
            if !fading, abs(scroller.alphaValue - target) > 0.02 {
                scroller.alphaValue = target
            }
        }

        private func nearestScrollView() -> NSScrollView? {
            var view: NSView? = self
            while let current = view {
                if let scroll = current as? NSScrollView {
                    return scroll
                }
                view = current.superview
            }
            return nil
        }
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

@MainActor
private final class ReasoningMenuProxy: NSObject {
    let handler: (ReasoningEffort) -> Void

    init(_ handler: @escaping (ReasoningEffort) -> Void) {
        self.handler = handler
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effort = ReasoningEffort(rawValue: raw)
        else { return }
        handler(effort)
    }
}

struct ErrorLipContent: View {
    var text: String
    var action: HUDErrorLip.Action
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(nsColor: HUDLipChrome.ink))
            Group {
                if action == .none {
                    message
                } else {
                    Button(action: onTap) { message }
                        .buttonStyle(.plain)
                }
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: HUDLipChrome.dismiss))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: HUDLayout.lipVisible)
    }

    private var message: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: HUDLipChrome.ink))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
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
