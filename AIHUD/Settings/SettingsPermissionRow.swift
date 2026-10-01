import AVFoundation
import Speech

struct SettingsPermissionRow: Identifiable {
    var id: String
    var title: String
    var status: String
    var buttonTitle: String
    var isGranted: Bool
    var prompt: () -> Void
}

enum SettingsPermissionRows {
    @MainActor
    static func make(model: HUDModel) -> [SettingsPermissionRow] {
        let screenGranted = CGPreflightScreenCaptureAccess()
        let accessibilityGranted = AccessibilityPermission.isTrusted
        return [
            SettingsPermissionRow(
                id: "voice",
                title: String(localized: "Microphone & Speech"),
                status: voiceStatus,
                buttonTitle: voiceButtonTitle,
                isGranted: VoicePermission.isGranted,
                prompt: { model.promptVoicePrivacyFromSettings() }
            ),
            SettingsPermissionRow(
                id: "screen",
                title: String(localized: "Screen Recording"),
                status: screenGranted
                    ? String(localized: "Allowed")
                    : String(localized: "Not granted. Request access or open System Settings."),
                buttonTitle: screenGranted
                    ? String(localized: "Allowed")
                    : String(localized: "Request Access…"),
                isGranted: screenGranted,
                prompt: { model.promptScreenPrivacyFromSettings() }
            ),
            SettingsPermissionRow(
                id: "accessibility",
                title: String(localized: "Accessibility"),
                status: accessibilityGranted
                    ? String(localized: "Allowed")
                    : String(localized: "Not granted. Window capture needs this."),
                buttonTitle: accessibilityGranted
                    ? String(localized: "Allowed")
                    : String(localized: "Request Access…"),
                isGranted: accessibilityGranted,
                prompt: { model.promptAccessibilityPrivacyFromSettings() }
            ),
        ]
    }

    private static var voiceStatus: String {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .authorized && speech == .authorized {
            return String(localized: "Allowed")
        }
        if mic == .denied || mic == .restricted || speech == .denied || speech == .restricted {
            return String(localized: "Denied. Open System Settings.")
        }
        return String(localized: "Not requested yet")
    }

    private static var voiceButtonTitle: String {
        if VoicePermission.isGranted { return String(localized: "Allowed") }
        let mic = VoicePermission.settingsDecision(for: AVCaptureDevice.authorizationStatus(for: .audio))
        let speech = VoicePermission.settingsDecision(forSpeech: SFSpeechRecognizer.authorizationStatus())
        if mic == .openSettings || speech == .openSettings {
            if mic == .request || speech == .request {
                return String(localized: "Request Access…")
            }
            return String(localized: "Open System Settings…")
        }
        return String(localized: "Request Access…")
    }
}
