import ApplicationServices
import Foundation

enum AccessibilityPermission {
    /// Settings control: prompt only when not trusted. Trusted → none.
    static func settingsDecision(trusted: Bool) -> PrivacyPromptDecision {
        trusted ? .none : .request
    }

    static func shouldPrompt(trusted: Bool) -> Bool {
        !trusted
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt via the system dialog when possible. Does nothing when already trusted.
    @discardableResult
    static func promptFromSettingsIfNeeded() -> Bool {
        let trusted = AXIsProcessTrusted()
        guard shouldPrompt(trusted: trusted) else { return true }
        // Literal matches kAXTrustedCheckOptionPrompt without touching the non-Sendable global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
