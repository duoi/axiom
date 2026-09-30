import Foundation

enum ChatTimeoutSettings {
    static let defaultsKey = "chat.requestTimeoutSeconds"
    static let defaultSeconds: TimeInterval = 45
    static let minimumSeconds: TimeInterval = 10
    static let maximumSeconds: TimeInterval = 600

    static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(maximumSeconds, max(minimumSeconds, value))
    }

    static func load(from defaults: UserDefaults) -> TimeInterval {
        guard defaults.object(forKey: defaultsKey) != nil else {
            return defaultSeconds
        }
        return clamp(defaults.double(forKey: defaultsKey))
    }

    static func save(_ value: TimeInterval, to defaults: UserDefaults) {
        defaults.set(clamp(value), forKey: defaultsKey)
    }

    static func resourceTimeout(forRequest request: TimeInterval) -> TimeInterval {
        clamp(request) * 2
    }
}
