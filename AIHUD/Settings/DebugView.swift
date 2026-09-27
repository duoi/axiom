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
                            Button("Failed") { send(.failed) }
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
                            Button("Disarm") { send(.disarmScreen) }
                        }
                        HStack {
                            Button("Listening") { send(.dictateOn) }
                            Button("Stop listening") { send(.dictateOff) }
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
                        Button("Clear status") { send(.clearStatus) }
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
        return "\(phase) · \(focus) · \(listening)"
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
