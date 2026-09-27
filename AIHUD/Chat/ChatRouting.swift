import Foundation

enum OnDeviceAvailability: Equatable, Sendable {
    case available
    case notEligible
    case notEnabled
    case notReady
    case other
}

enum ChatRoute: Equatable, Sendable {
    case onDevice
    case cloud(SendTarget)
    case blocked(String)
}

enum ChatSettings {
    static let onDeviceKey = "chat.onDevice"
    static let modelKey = "endpoint.model"
    static let urlKey = "endpoint.completionsURL"

    static func loadOnDevice(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: onDeviceKey)
    }

    static func saveOnDevice(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: onDeviceKey)
    }
}

enum ChatRouting {
    static let appleIntelligenceOff = "Apple Intelligence is off."
    static let macNotEligible = "This Mac is not eligible for Apple Intelligence."
    static let modelNotReady = "The on-device model is still downloading."
    static let modelUnavailable = "The on-device model is not available."
    static let cannotTakeImage = "The on-device model cannot take that image."

    static func decide(
        onDevice: Bool,
        availability: OnDeviceAvailability,
        cloud: SendTarget,
        hasImage: Bool = false,
        visionConfigured: Bool = false,
        supportsOnDeviceImage: Bool = false
    ) -> ChatRoute {
        if !onDevice {
            return .cloud(cloud)
        }
        switch availability {
        case .available:
            break
        case .notEnabled:
            return .blocked(appleIntelligenceOff)
        case .notEligible:
            return .blocked(macNotEligible)
        case .notReady:
            return .blocked(modelNotReady)
        case .other:
            return .blocked(modelUnavailable)
        }
        if hasImage, visionConfigured {
            return .cloud(cloud)
        }
        if hasImage, !supportsOnDeviceImage {
            return .blocked(cannotTakeImage)
        }
        return .onDevice
    }

    static func message(for availability: OnDeviceAvailability) -> String? {
        switch availability {
        case .available:
            return nil
        case .notEnabled:
            return appleIntelligenceOff
        case .notEligible:
            return macNotEligible
        case .notReady:
            return modelNotReady
        case .other:
            return modelUnavailable
        }
    }
}
