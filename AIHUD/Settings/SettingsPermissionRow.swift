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
                title: "Microphone & Speech",
                status: voiceStatus,
                buttonTitle: voiceButtonTitle,
                isGranted: VoicePermission.isGranted,
                prompt: { model.promptVoicePrivacyFromSettings() }
            ),
            SettingsPermissionRow(
                id: "screen",
                title: "Screen Recording",
                status: screenGranted ? "Allowed" : "Not granted — request or open System Settings",
                buttonTitle: screenGranted ? "Allowed" : "Request Access…",
                isGranted: screenGranted,
                prompt: { model.promptScreenPrivacyFromSettings() }
            ),
            SettingsPermissionRow(
                id: "accessibility",
                title: "Accessibility",
                status: accessibilityGranted ? "Allowed" : "Not granted — needed for Window capture",
                buttonTitle: accessibilityGranted ? "Allowed" : "Request Access…",
                isGranted: accessibilityGranted,
                prompt: { model.promptAccessibilityPrivacyFromSettings() }
            ),
        ]
    }

    private static var voiceStatus: String {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .authorized && speech == .authorized {
            return "Allowed"
        }
        if mic == .denied || mic == .restricted || speech == .denied || speech == .restricted {
            return "Denied — open System Settings"
        }
        return "Not requested yet"
    }

    private static var voiceButtonTitle: String {
        if VoicePermission.isGranted { return "Allowed" }
        let mic = VoicePermission.settingsDecision(for: AVCaptureDevice.authorizationStatus(for: .audio))
        let speech = VoicePermission.settingsDecision(forSpeech: SFSpeechRecognizer.authorizationStatus())
        if mic == .openSettings || speech == .openSettings {
            if mic == .request || speech == .request {
                return "Request Access…"
            }
            return "Open System Settings…"
        }
        return "Request Access…"
    }
}
