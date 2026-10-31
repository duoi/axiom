import AppKit
import KeyboardShortcuts
import SwiftUI

struct HUDView: View {
    @Bindable var model: HUDModel
    var store: EndpointStore
    /// Offscreen height probe. It must not take the live prompt editor or report line height.
    var measuresOnly = false
    var region: HUDChromeRegion = .plate
    @State private var promptHeight = HUDMetrics.rowHeight
    @State private var scrollerVisible = false
    @Bindable private var preview = DebugPreviewStore.shared

    var body: some View {
        switch region {
        case .plate:
            plate
        case .capsule:
            capsule
        case .pill(let id):
            pill(id)
        }
    }

    private var plate: some View {
        let override = model.logoOverride
        return VStack(alignment: .leading, spacing: 0) {
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
                historyExpanded: model.historyExpanded,
                toolLine: model.toolLine
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

    private var capsule: some View {
        let override = model.logoOverride
        let showsReply = HistoryChromePolicy.showsReplyRegion(
            answer: model.session.displayAnswer,
            phase: model.session.phase,
            historyExpanded: model.historyExpanded,
            toolLine: model.toolLine
        )
        return VStack(alignment: .leading, spacing: 0) {
            promptRow(
                idleSlot: HUDModelMenu.idleSlot(
                    dictating: model.dictating,
                    override: override,
                    endpoint: store.selectedEndpoint ?? ChatEndpointCatalog.onDeviceEndpoint
                ),
                orbChoice: preview.cardOrb,
                showsSend: false
            )
            if !model.session.chips.isEmpty {
                chipRow
                    .opacity(model.splitChipOpacity)
            }
            if showsReply {
                hairline
                history
            }
        }
        .frame(width: HUDMetrics.cardWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .onChange(of: store.experimentalAgent) { relayout() }
        .onChange(of: store.savesHistory) { relayout() }
        .onChange(of: model.displayedCaptureTarget) { relayout() }
        .onChange(of: model.captureArmed) { relayout() }
        .onChange(of: model.session.preset) { relayout() }
        .onChange(of: store.showsPresetControl) { relayout() }
    }

    /// Only the live card asks for layout. The measuring copy and each pill see the same changes.
    private func relayout() {
        guard !measuresOnly, !isPill else { return }
        model.onLayout()
    }

    @ViewBuilder
    private func pill(_ id: HUDPillID) -> some View {
        Group {
            switch id {
            case .preset:
                presetToggle
            case .capture:
                captureControl
            case .context:
                contextButton(showsLabel: true)
            case .contextIcon:
                contextButton(showsLabel: false)
            case .shortcut:
                Group {
                    if store.savesHistory {
                        historyGhostButton
                    } else {
                        Text(shortcutLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .help("Show or hide the card. \(shortcutKeys(.hideCard)) hides it.")
                    }
                }
                .animation(pillMotion ? .easeInOut(duration: 0.08) : nil, value: store.savesHistory)
            case .mic:
                micButton
            case .send:
                sendControl(symbol: "arrow.up", orbChoice: preview.cardOrb)
            }
        }
        .padding(.horizontal, id.isCircle ? 0 : 16)
        .frame(
            minWidth: id.isCircle ? HUDSplitChromeLayout.pillHeight : nil,
            maxWidth: id.isCircle ? HUDSplitChromeLayout.pillHeight : nil
        )
        .frame(height: HUDSplitChromeLayout.pillHeight)
        .background {
            // A pill is already its own bubble, so the selection fills all of it.
            if pillHighlighted(id) {
                HUDSelectionFill()
            }
        }
        .animation(pillMotion ? .easeInOut(duration: 0.16) : nil, value: pillHighlighted(id))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func pillHighlighted(_ id: HUDPillID) -> Bool {
        switch id {
        case .preset: model.session.preset == .agent
        case .capture: model.captureArmed
        default: false
        }
    }

    private var isPill: Bool {
        if case .pill = region { return true }
        return false
    }

    private var pillMotion: Bool {
        guard case .pill = region else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var symbolReplace: ContentTransition {
        pillMotion ? .symbolEffect(.replace) : .identity
    }

    private func promptRow(
        idleSlot: HUDIdleSlot,
        orbChoice: ThinkingOrbChoice,
        showsSend: Bool = true
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
                        .help("Choose the chat model")
                        .accessibilityLabel("Choose the chat model")
                }
            }
            .id(model.logoOverride)
            .frame(width: 18, height: 18)
            PromptField(
                text: Binding(
                    get: { model.session.draft },
                    set: { model.setDraft($0) }
                ),
                placeholder: model.dictating && model.session.draft.isEmpty
                    ? String(localized: "Listening...")
                    : String(localized: "Ask anything..."),
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
                    let line = PromptLayout.promptLineHeight
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
            if showsSend {
                sendControl(symbol: "arrow.up.right", orbChoice: orbChoice)
            }
        }
        .frame(
            width: HUDLayout.rowWidth,
            height: model.displayedMultiline ? promptHeight : HUDMetrics.rowHeight
        )
        .padding(.horizontal, HUDMetrics.inset)
        .onChange(of: model.displayedMultiline) {
            if !model.displayedMultiline {
                promptHeight = HUDMetrics.rowHeight
                guard !measuresOnly else { return }
                model.promptLineCount = 1
            }
            relayout()
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
                        .help("Remove \(chip.name)")
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
                    middleScroll(height: HUDLayout.replyBodyHeight(lines: HUDLayout.replyMaxLines)) {
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
                hasUserTurns: model.session.turns.contains(where: { $0.role == .user }),
                toolLine: model.toolLine
            ) {
                Button(action: model.toggleHistory) {
                    Image(systemName: model.historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.historyExpanded
                      ? String(localized: "Show the reply")
                      : String(localized: "Show the thread"))
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
        return Group {
            if model.session.phase == .waiting, text.isEmpty, !showsToolStatus {
                EmptyView()
            } else if lines > HUDLayout.replyMaxLines {
                VStack(alignment: .leading, spacing: 6) {
                    middleScroll(height: bodyHeight) {
                        compactReplyText(text)
                    }
                    if showsToolStatus {
                        toolStatus
                            .padding(.leading, HUDMetrics.inset)
                            .padding(.trailing, HUDMetrics.inset + HUDMetrics.controlSize)
                            .padding(.bottom, 12)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !text.isEmpty {
                        compactReplyText(text)
                            .frame(height: bodyHeight, alignment: .top)
                    }
                    if showsToolStatus {
                        toolStatus
                    }
                }
                .padding(.leading, HUDMetrics.inset)
                .padding(.trailing, HUDMetrics.inset + HUDMetrics.controlSize)
                .padding(.vertical, 12)
                .onAppear { scrollerVisible = false }
            }
        }
        .font(Font(HUDLayout.replyFont))
    }

    private var showsToolStatus: Bool {
        if let line = model.toolLine, !line.isEmpty { return true }
        return model.hasPendingOpen
    }

    private var toolStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = model.toolLine, !line.isEmpty {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.hasPendingOpen {
                HStack(spacing: 12) {
                    Button("Allow") { model.allowPendingOpen() }
                    Button("Deny") { model.denyPendingOpen() }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func compactReplyText(_ text: String) -> some View {
        Text(HUDLayout.styledReply(text))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func middleScroll<Content: View>(
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ReplyScroll(
            height: height,
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
            if showsToolStatus {
                toolStatus
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
                if store.showsPresetControl {
                    presetToggle
                }
                captureControl
                contextButton()
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

    private func contextButton(showsLabel: Bool = true) -> some View {
        Button(action: model.addContext) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                if showsLabel {
                    Text("Add context")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Attach a file. Up to 4 files, 4 MB each. \(shortcutKeys(.addContext))")
        .accessibilityLabel("Add context")
    }

    private func sendControl(symbol: String, orbChoice: ThinkingOrbChoice) -> some View {
        let showsOrb = ReplyWaitingChrome.showsComposingOrb(
            phase: model.session.phase,
            answer: model.session.displayAnswer
        )
        let symbolName = model.session.showsStop ? "stop.fill" : symbol
        let canPress = model.session.canSend || model.captureArmed || model.session.showsStop
        return Button(action: model.submitOrStop) {
            ZStack {
                if showsOrb {
                    AnimatedThinkingOrb(choice: orbChoice)
                        .transition(.opacity)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .contentTransition(symbolReplace)
                        .transition(.opacity)
                }
            }
            .animation(pillMotion ? .easeInOut(duration: 0.12) : nil, value: showsOrb)
        }
        .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(model.session.showsStop
              ? String(localized: "Stop")
              : String(localized: "Send. \(shortcutKeys(.send))"))
        .opacity(canPress ? 0.9 : 0.35)
        .disabled(!canPress)
    }

    private var micButton: some View {
        Button(action: model.toggleDictation) {
            Image(systemName: model.dictating ? "waveform" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.dictating ? Color.orange : Color.secondary)
                .contentTransition(symbolReplace)
                .symbolEffect(.variableColor.iterative, isActive: model.dictating)
                .animation(pillMotion ? .easeInOut(duration: 0.16) : nil, value: model.dictating)
                .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
        }
        .buttonStyle(.plain)
        .help(model.dictating
              ? String(localized: "Stop dictation. \(shortcutKeys(.toggleDictation))")
              : String(localized: "Dictate into the prompt. \(shortcutKeys(.toggleDictation))"))
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
                        .contentTransition(symbolReplace)
                    Text(model.session.preset.title)
                        .contentTransition(pillMotion ? .opacity : .identity)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .animation(pillMotion ? .easeInOut(duration: 0.16) : nil, value: model.session.preset)
            .hudCapsule(highlighted: model.session.preset == .agent && !isPill)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(model.session.preset == .agent
              ? String(localized: "Agent can use tools. \(shortcutKeys(.cyclePreset)) switches to Ask.")
              : String(localized: "Ask answers without tools. \(shortcutKeys(.cyclePreset)) switches to Agent."))
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
                            .contentTransition(symbolReplace)
                        Text(model.displayedCaptureTarget.title)
                            .contentTransition(pillMotion ? .opacity : .identity)
                    }
                    .animation(pillMotion ? .easeInOut(duration: 0.12) : nil, value: model.displayedCaptureTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(captureHelp)
                Spacer(minLength: 6)
                Button(action: popCaptureMenu) {
                    toolbarChevron
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose Screen or Window")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(tint)
        .hudCapsule(highlighted: model.captureArmed && !isPill)
        .fixedSize()
    }

    private var captureHelp: String {
        let window = model.displayedCaptureTarget == .window
        let keys = shortcutKeys(.cycleCapture)
        if model.captureArmed {
            return window
                ? String(localized: "The next send includes the front window. \(keys)")
                : String(localized: "The next send includes the display. \(keys)")
        }
        return window
            ? String(localized: "Include the front window on the next send. \(keys)")
            : String(localized: "Include the display on the next send. \(keys)")
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
        let reasoning = NSMenuItem(title: String(localized: "Reasoning"), action: nil, keyEquivalent: "")
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
                .animation(pillMotion ? .easeInOut(duration: 0.16) : nil, value: model.historyExcluded)
                .frame(width: HUDMetrics.controlSize, height: HUDMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.historyExcluded
              ? String(localized: "This chat is not saved. \(shortcutKeys(.toggleIncognito)) saves it.")
              : String(localized: "This chat is saved. \(shortcutKeys(.toggleIncognito)) skips it."))
        .accessibilityLabel(model.historyExcluded
            ? String(localized: "Recording off")
            : String(localized: "Recording on"))
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
            .help("Show or hide the card. \(shortcutKeys(.hideCard)) hides it.")
    }

    private func shortcutKeys(_ name: KeyboardShortcuts.Name) -> String {
        CardShortcutBindings.label(for: name)
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
    @Binding var stickToBottom: Bool
    @Binding var scrollerVisible: Bool
    @ViewBuilder var content: Content
    @State private var fade = HUDLayout.ScrollFadeEdges.none
    @State private var hideTask: Task<Void, Never>?
    @State private var userScrolling = false

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay {
                ScrollView {
                    content
                        .background {
                            OverlayScrollerInstaller(
                                active: scrollerVisible,
                                pinToBottom: stickToBottom
                            )
                        }
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
                    userScrolling = live
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
                    // The probe below pins the tail during layout; SwiftUI's scrollTo snapped to the top mid-stream.
                    stickToBottom = HUDLayout.tailFollow(
                        following: stickToBottom,
                        fits: next.fits,
                        atBottom: next.atBottom,
                        userScrolling: userScrolling
                    )
                }
            }
            .clipShape(Rectangle())
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
    var pinToBottom: Bool

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.active = active
        view.pinToBottom = pinToBottom
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.active = active
        if !pinToBottom {
            nsView.releasePinHold()
        }
        nsView.pinToBottom = pinToBottom
        nsView.install()
    }

    final class Probe: NSView {
        var active = false
        var pinToBottom = false
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
            observe(scroll)
            if !configured {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.hasVerticalScroller = true
                scroll.hasHorizontalScroller = false
                scroll.horizontalScrollElasticity = .none
                configured = true
            }
            if let scroller = scroll.verticalScroller {
                scroller.isHidden = false
                let target: CGFloat = active ? 1 : 0
                if applied == nil {
                    scroller.alphaValue = target
                    applied = active
                } else if applied != active {
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
                } else if !fading, abs(scroller.alphaValue - target) > 0.02 {
                    scroller.alphaValue = target
                }
            }
            if pinToBottom, !suppressPin {
                pinBottom(scroll)
            }
        }

        private var pinning = false
        private var suppressPin = false
        private var userDragging = false
        private weak var observedScroll: NSScrollView?

        func releasePinHold() {
            guard !userDragging else { return }
            suppressPin = false
        }

        private func observe(_ scroll: NSScrollView) {
            guard observedScroll !== scroll else { return }
            if observedScroll != nil {
                NotificationCenter.default.removeObserver(self)
            }
            observedScroll = scroll
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveScrollStarted(_:)),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scroll
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveScrollEnded(_:)),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scroll
            )
        }

        @objc private func liveScrollStarted(_ note: Notification) {
            userDragging = true
            suppressPin = true
        }

        @objc private func liveScrollEnded(_ note: Notification) {
            userDragging = false
            guard let scroll = note.object as? NSScrollView else {
                suppressPin = false
                return
            }
            if clipIsAtBottom(scroll) {
                suppressPin = false
                if pinToBottom {
                    pinBottom(scroll)
                }
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func pinBottom(_ scroll: NSScrollView) {
            guard !pinning, let document = scroll.documentView else { return }
            pinning = true
            defer { pinning = false }
            let clip = scroll.contentView
            let overflow = document.bounds.height - clip.bounds.height
            guard overflow > 1 else { return }
            let y = clip.isFlipped ? overflow : 0
            guard abs(clip.bounds.origin.y - y) > 1, glideTarget != y else { return }
            let target = NSPoint(x: clip.bounds.origin.x, y: y)
            let duration = HUDFrameMotion.duration(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            // Glide a streamed line or two; jump when the reply first turns into a scroll view.
            guard duration > 0, abs(clip.bounds.origin.y - y) < clip.bounds.height / 2 else {
                glideTarget = nil
                clip.scroll(to: target)
                scroll.reflectScrolledClipView(clip)
                return
            }
            glideTarget = y
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(target)
            }, completionHandler: { [weak self] in
                if self?.glideTarget == y { self?.glideTarget = nil }
                scroll.reflectScrolledClipView(clip)
            })
        }

        private var glideTarget: CGFloat?

        private func clipIsAtBottom(_ scroll: NSScrollView) -> Bool {
            guard let document = scroll.documentView else { return true }
            let clip = scroll.contentView
            let overflow = document.bounds.height - clip.bounds.height
            if overflow <= 1 { return true }
            let y = clip.isFlipped ? overflow : 0
            return abs(clip.bounds.origin.y - y) < 24
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
