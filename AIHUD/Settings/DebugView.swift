import SwiftUI

struct DebugView: View {
    var model: HUDModel
    var onCommand: (String) -> Void
    @Bindable private var preview = DebugPreviewStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                debugCard {
                    Text(statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Reset to idle") { send(.reset) }
                    Button("Open transcript") {
                        onCommand("open-transcript")
                    }
                    Text("Opens a second window that streams redacted raw HTTP request and response lines for chat sends.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                labeled("Chat and vision") {
                    debugCard {
                        Text(chatLine)
                        Text(visionLine)
                            .foregroundStyle(.secondary)
                        if readyChatItems.isEmpty {
                            Text("No ready saved providers. Forcing a logo does not sign in or write a key.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Apply a ready saved row as the chat model. This does not start OAuth or clear keys.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ForEach(readyChatItems, id: \.providerID) { item in
                                Button("Chat: \(item.title)") {
                                    applyReadyChat(item)
                                }
                            }
                        }
                    }
                }

                labeled("Provider mark") {
                    debugCard {
                        Text("Display-only. Does not change chat.defaultEndpointID, chat.chatModelID, or vision ids. The waveform still wins while listening.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 108), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(DebugRouting.logoChoices) { choice in
                                Button(choice.title) { onCommand(choice.command) }
                            }
                        }
                        Button("Apply as chat model") {
                            model.applyDebugLogoAsChat()
                        }
                        .disabled(model.logoOverride == nil)
                    }
                }

                labeled("Phase") {
                    debugCard {
                        HStack {
                            Button("Empty") { send(.composingEmpty) }
                            Button("Draft") { send(.composingDraft) }
                        }
                        HStack {
                            Button("Waiting") { send(.waiting) }
                            Button("Streaming") { send(.streaming) }
                        }
                        HStack {
                            Button("Finished") { send(.finished) }
                            Button("Second turn") { send(.secondTurn) }
                        }
                        HStack {
                            Button("Failed") { send(.failed) }
                            Button("Markdown reply") { send(.markdownReply) }
                        }
                        HStack {
                            Button("10 lines") { send(.reply10) }
                            Button("20 lines") { send(.reply20) }
                        }
                        HStack {
                            Button("Streaming single line") { send(.streamLine) }
                            Button("Streaming multi line") { send(.streamMulti) }
                        }
                        HStack {
                            Button("Full lower extension") { send(.lowerExtension) }
                            Button("Full upper extension") { send(.upperExtension) }
                        }
                        HStack {
                            Button("Overflow scroll") { send(.replyOverflow) }
                            Button("Expanded conversation") { send(.expandedConversation) }
                        }
                        HStack {
                            Button("Stream sun") { send(.streamSun) }
                        }
                    }
                }

                labeled("Focus") {
                    debugCard {
                        HStack {
                            Button("Make card key") { send(.makeKey) }
                            Button("Resign key") { send(.resignKey) }
                        }
                        Text("Compare matte versus clear glass and the pill backdrop. Matte still skips the window shadow.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                labeled("Toolbar") {
                    debugCard {
                        HStack {
                            Button("Ask") { send(.ask) }
                            Button("Agent") { send(.agent) }
                        }
                        HStack {
                            Button("Arm Screen") { send(.armScreen) }
                            Button("Arm Window") { send(.armWindow) }
                            Button("Disarm") { send(.disarmScreen) }
                        }
                        HStack {
                            Button("Listening") { send(.dictateOn) }
                            Button("Stop listening") { send(.dictateOff) }
                        }
                        Button("Flash capture glow") { send(.flashHighlight) }
                        HStack {
                            Button("Multiline on") { send(.multilineOn) }
                            Button("Multiline off") { send(.multilineOff) }
                        }
                        HStack {
                            Button("Expand history") { send(.historyOn) }
                            Button("Collapse history") { send(.historyOff) }
                        }
                        Button("Add context chip") { send(.addChip) }
                        Text("Listening glows the whole card with the Listening preset. Flash capture glow uses the Capture preset for one second.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                labeled("Intelligence Glow") {
                    intelligenceGlowDebug
                }

                labeled("Thinking orb") {
                    thinkingOrbDebug
                }

                labeled("Status") {
                    debugCard {
                        Button("Mic denied") { send(.micDenied) }
                        Button("Speech denied") { send(.speechDenied) }
                        Button("Generic failure") { send(.genericFailure) }
                        Button("Missing endpoint") { send(.missingEndpoint) }
                        Button("Missing key") { send(.missingKey) }
                        Button("Missing model") { send(.missingModel) }
                        Button("Sign in") { send(.signIn) }
                        Button("Request failed") { send(.requestFailed) }
                        Button("Clear status") { send(.clearStatus) }
                        Text("Sign-in copy is this button only. Forcing a provider logo does not show it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(HUDMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: HUDMetrics.debugSize.width, minHeight: HUDMetrics.debugSize.height - 40)
    }

    private var statusLine: String {
        let phase: String
        switch model.session.phase {
        case .composing: phase = "composing"
        case .waiting: phase = "waiting"
        case .streaming: phase = "streaming"
        case .finished: phase = "finished"
        case .failed: phase = "failed"
        }
        let focus = model.cardIsKey ? "key" : "resigned"
        let listening = model.dictating ? "listening" : "idle mic"
        let mark = model.logoOverride?.accessibilityName ?? "live mark"
        return "\(phase) · \(focus) · \(listening) · \(mark)"
    }

    private var chatLine: String {
        let name = model.store.selectedEndpoint?.name ?? "none"
        let modelID = model.store.chatModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelID.isEmpty {
            return "Chat: \(name)"
        }
        return "Chat: \(name) · \(modelID)"
    }

    private var visionLine: String {
        let name = model.store.visionEndpoint?.name ?? "none"
        let modelID = model.store.visionModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelID.isEmpty {
            return "Vision: \(name)"
        }
        return "Vision: \(name) · \(modelID)"
    }

    private var readyChatItems: [HUDModelMenu.Item] {
        HUDModelMenu.items(
            endpoints: model.store.endpoints,
            chatID: model.store.defaultEndpointID,
            chatModelID: model.store.chatModelID,
            secret: { model.store.apiKey(for: $0) },
            onDeviceReady: OnDeviceChat.availability == .available
        )
    }

    private var thinkingOrbDebug: some View {
        debugCard {
            Text("Session-only. Real waits use Composing unless Debug is on. Glow choices tint the dots with the intelligence conic palette. Pulsing orb is from AI-Animation-Demo.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Orb", selection: $preview.orbChoice) {
                ForEach(ThinkingOrbChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            HStack(spacing: 12) {
                AnimatedThinkingOrb(choice: preview.orbChoice)
                Text(preview.orbChoice.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Force Waiting") { send(.waiting) }
            Button("In-flight prompt") {
                preview.orbChoice = .pulsingOrb
                onCommand(DebugCommand.inFlightPrompt.rawValue)
            }
            Text("In-flight prompt keeps the draft visible with shimmer and uses the Pulsing orb on send.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text("Text shimmers from AI-Animation-Demo. Default send uses ChatGPT style unless Debug picks another.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Shimmer", selection: $preview.shimmerStyle) {
                ForEach(InFlightShimmerStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                InFlightPromptShimmer(
                    text: "Locked draft while the reply streams in.",
                    style: preview.shimmerStyle
                )
                Text(preview.shimmerStyle.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Preview shimmer") {
                preview.orbChoice = .pulsingOrb
                onCommand(preview.shimmerStyle.debugCommand)
            }
        }
    }

    private var intelligenceGlowDebug: some View {
        debugCard {
            Text("Session-only. Listening loads the Listening preset; Flash capture glow loads Capture. Sliders edit the active context.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Context", selection: $preview.activeContext) {
                ForEach(IntelligenceGlowContext.allCases) { context in
                    Text(context.title).tag(context)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: preview.activeContext) { _, _ in
                preview.notify()
            }

            Picker("Variation", selection: $preview.activePreset.variation) {
                ForEach(IntelligenceGlowVariation.allCases) { variation in
                    Text(variation.title).tag(variation)
                }
            }
            .onChange(of: preview.activePreset.variation) { _, _ in
                preview.notify()
            }

            sliderRow("Padding", value: $preview.activePreset.padding, range: 2...40)
            sliderRow("Line width scale", value: $preview.activePreset.lineWidthScale, range: 0.2...2)
            sliderRow("Blur scale", value: $preview.activePreset.blurScale, range: 0.2...2.5)
            sliderRow("Opacity", value: $preview.activePreset.opacity, range: 0.1...1)
            sliderRow("Update interval", value: $preview.activePreset.updateInterval, range: 0.15...1.2)
            sliderRow("Animation speed", value: $preview.activePreset.animationSpeed, range: 0.25...3)

            Text("Sweep")
                .font(.subheadline.weight(.semibold))
            sliderRow("blurRadius", value: $preview.activePreset.blurRadius, range: 2...60)
            sliderRow("lineWidth", value: $preview.activePreset.sweepLineWidth, range: 0.3...4)
            sliderRow("sweepSpan", value: $preview.activePreset.sweepSpan, range: 20...220)
            sliderRow("sweepOffset", value: $preview.activePreset.sweepOffset, range: 0...320)

            HStack {
                Button("Reset active preset") { preview.resetActivePreset() }
                Button("Reset both presets") { preview.resetBothPresets() }
            }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in
                    preview.notify()
                }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in
                    preview.notify()
                }
        }
    }

    private func applyReadyChat(_ item: HUDModelMenu.Item) {
        guard let modelID = item.models.first(where: \.enabled)?.id else { return }
        model.selectChat(providerID: item.providerID, modelID: modelID)
    }

    private func send(_ command: DebugCommand) {
        onCommand(command.rawValue)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func debugCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
