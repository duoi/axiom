import SwiftUI

struct DebugView: View {
    var model: HUDModel
    var onCommand: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                debugCard {
                    Text(statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Reset to idle") { send(.reset) }
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
                        HStack {
                            Button("Multiline on") { send(.multilineOn) }
                            Button("Multiline off") { send(.multilineOff) }
                        }
                        HStack {
                            Button("Expand history") { send(.historyOn) }
                            Button("Collapse history") { send(.historyOff) }
                        }
                        Button("Add context chip") { send(.addChip) }
                        Text("Listening only flips the waveform and placeholder. It does not open the microphone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
