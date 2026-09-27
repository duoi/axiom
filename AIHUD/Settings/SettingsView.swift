import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var store: EndpointStore
    var onSave: () -> Void

    var body: some View {
        Form {
            TextField("Base URL", text: $store.completionsURL)
            TextField("Model", text: $store.model)
            SecureField("API key", text: $store.apiKey)
            KeyboardShortcuts.Recorder("Show HUD", name: .toggleHUD)
            HStack {
                Spacer()
                Button("Save") {
                    store.save()
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 440)
    }
}
