import Foundation

enum PrivacyPromptDecision: Equatable, Sendable {
    case none
    case request
    case openSettings
    case requestAndOpenSettings
}

enum PrivacyPromptURL {
    private static let privacySecurityBase =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    private static let legacyScreenCapture =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    private static let legacyAccessibility =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static var microphone: URL? {
        URL(string: "\(privacySecurityBase)?Privacy_Microphone")
    }

    static var speechRecognition: URL? {
        URL(string: "\(privacySecurityBase)?Privacy_SpeechRecognition")
    }

    static var screenRecording: URL? {
        URL(string: legacyScreenCapture)
    }

    static var accessibility: URL? {
        URL(string: legacyAccessibility)
    }
}
