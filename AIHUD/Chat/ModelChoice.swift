import Foundation

struct ServiceCredentials: Equatable, Sendable {
    var url: String
    var model: String
    var apiKey: String
    var kind: EndpointKind = .openaiCompatible

    var isComplete: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .chatgptSubscription ? ChatGPTAuth.parse(apiKey) != nil : !apiKey.isEmpty)
    }
}

enum ModelChoice {
    /// A vision service is used only when the request carries an image and that service is fully set.
    static func pick(chat: ServiceCredentials, vision: ServiceCredentials, hasImage: Bool) -> ServiceCredentials {
        if hasImage, vision.isComplete {
            return vision
        }
        return chat
    }

    static func visionIsIncomplete(_ vision: ServiceCredentials) -> Bool {
        let url = vision.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !url.isEmpty && !vision.isComplete
    }
}
