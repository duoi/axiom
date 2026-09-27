import KeyboardShortcuts
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case chat
    case vision
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .chat: "Chat"
        case .vision: "Vision"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .chat: "text.bubble"
        case .vision: "eye"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var store: EndpointStore
    @Bindable var model: HUDModel
    @State private var page: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: HUDMetrics.sidebarWidth)
            .padding(.top, HUDMetrics.inset)

            Divider()

            Group {
                switch page {
                case .general:
                    generalPane
                case .appearance:
                    appearancePane
                case .chat:
                    chatPane
                case .vision:
                    visionPane
                case .about:
                    aboutPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: HUDMetrics.settingsSize.width, minHeight: HUDMetrics.settingsSize.height - 40)
    }

    private var generalPane: some View {
        settingsPane {
            SettingsCard {
                Toggle("Keep the card up", isOn: $store.keepHovering)
                Text("When this is on, clicking another window leaves the card in place. Escape or the hotkey still dismisses it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Wake on Axiom", isOn: Binding(
                    get: { store.wakeOnAxiom },
                    set: { model.onSetWake($0) }
                ))
                Text("Listen for Axiom and show the card. Permission is requested here, not from the card.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Pause to send", isOn: $store.pauseToSend)
                Text("About 2 seconds of silence after a non-empty draft sends. Return still sends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let status = model.voiceStatus, !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(VoiceStatusCopy.adHocPermission)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                KeyboardShortcuts.Recorder("Hotkey", name: .toggleHUD)
            }
        }
    }

    private var appearancePane: some View {
        settingsPane {
            SettingsCard {
                Picker("Finish", selection: $store.usesMatte) {
                    Text("Glass").tag(false)
                    Text("Matte").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Glass is the clear card. Matte is the heavier glass. Neither is a solid fill.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                Text("Glass amount")
                Slider(value: $store.glassPercent, in: 0...100)
                Text("\(Int(store.glassPercent.rounded()))%")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("100% leaves the glass clear. Lower values add a quiet veil.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chatPane: some View {
        settingsPane {
            SettingsCard {
                Toggle("On-device model", isOn: $store.usesOnDevice)
                Text("Uses Apple Intelligence on this Mac. The endpoint fields stay in place.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Base URL", text: $store.completionsURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $store.model)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: $store.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("OpenAI-compatible Chat Completions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Save") { store.save() }
            }
        }
    }

    private var visionPane: some View {
        settingsPane {
            SettingsCard {
                TextField("Base URL", text: $store.visionURL, prompt: Text("Same as chat"))
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $store.visionModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: $store.visionAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used only when a message includes an image. Leave the URL empty to send images to the chat endpoint.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Save") { store.save() }
            }
        }
    }

    private var aboutPane: some View {
        settingsPane {
            VStack(spacing: HUDMetrics.controlSpacing) {
                AxiomLogo()
                    .frame(width: 88, height: 64)
                Text("AI HUD")
                    .font(.title2.weight(.semibold))
                Text("Version \(appVersion)")
                    .foregroundStyle(.secondary)
                Text("Steven Johns")
                Link("github.com/duoi/axiom", destination: URL(string: "https://github.com/duoi/axiom")!)
                Text("MIT License")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func settingsPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
                content()
            }
            .padding(HUDMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
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
