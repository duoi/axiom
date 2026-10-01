import AppKit
import SwiftUI

struct ModelRoleSection: View {
    let title: String
    let detail: String
    @Bindable var store: EndpointStore
    @Binding var providerID: UUID?
    @Binding var modelID: String
    var allowsUnset: Bool
    @State private var isListing = false

    private var provider: ChatEndpoint? {
        guard let providerID else { return nil }
        return store.endpoints.first(where: { $0.id == providerID })
    }

    private var isOnDevice: Bool {
        provider.map(ChatEndpointCatalog.isOnDevice) ?? false
    }

    private var availableModels: [String] {
        provider?.availableModels ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.controlSpacing) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Provider", selection: $providerID) {
                if allowsUnset {
                    Text("Same as chat").tag(Optional<UUID>.none)
                }
                ForEach(store.endpoints) { endpoint in
                    Text(endpoint.name).tag(Optional(endpoint.id))
                }
            }
            if providerID != nil || !allowsUnset {
                if isOnDevice {
                    Text("Apple Intelligence")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else if availableModels.isEmpty {
                    TextField("Model id", text: $modelID)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Model", selection: $modelID) {
                        ForEach(availableModels, id: \.self) { id in
                            Text(id).tag(id)
                        }
                        if !availableModels.contains(modelID) && !modelID.isEmpty {
                            Text(modelID).tag(modelID)
                        }
                        if modelID.isEmpty {
                            Text("Choose a model").tag("")
                        }
                    }
                }
            }
            if let provider, !isOnDevice {
                HStack {
                    Button("Refresh") {
                        Task { await refresh() }
                    }
                    .disabled(isListing)
                    if let error = store.modelListErrors[provider.id], !error.isEmpty {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func refresh() async {
        guard let id = providerID else { return }
        isListing = true
        defer { isListing = false }
        await store.refreshModels(for: id)
    }
}
