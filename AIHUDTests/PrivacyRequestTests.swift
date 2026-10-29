import AVFoundation
import Speech
import Testing
@testable import Axiom

@Test func microphoneSettingsDecision() {
    #expect(VoicePermission.settingsDecision(for: .notDetermined) == .request)
    #expect(VoicePermission.settingsDecision(for: .denied) == .openSettings)
    #expect(VoicePermission.settingsDecision(for: .restricted) == .openSettings)
    #expect(VoicePermission.settingsDecision(for: .authorized) == .none)
}

@Test func speechSettingsDecision() {
    #expect(VoicePermission.settingsDecision(forSpeech: .notDetermined) == .request)
    #expect(VoicePermission.settingsDecision(forSpeech: .denied) == .openSettings)
    #expect(VoicePermission.settingsDecision(forSpeech: .restricted) == .openSettings)
    #expect(VoicePermission.settingsDecision(forSpeech: .authorized) == .none)
}

@Test func microphoneRequestOnlyWhenNotDetermined() {
    #expect(VoicePermission.shouldRequestAccess(for: .notDetermined))
    #expect(!VoicePermission.shouldRequestAccess(for: .authorized))
    #expect(!VoicePermission.shouldRequestAccess(for: .denied))
    #expect(!VoicePermission.shouldRequestAccess(for: .restricted))
}

@Test func speechRequestOnlyWhenNotDetermined() {
    #expect(VoicePermission.shouldRequestSpeech(for: .notDetermined))
    #expect(!VoicePermission.shouldRequestSpeech(for: .authorized))
    #expect(!VoicePermission.shouldRequestSpeech(for: .denied))
    #expect(!VoicePermission.shouldRequestSpeech(for: .restricted))
}

@Test func screenRecordingSettingsDecision() {
    #expect(ScreenGrab.settingsDecision(preflightGranted: false) == .requestAndOpenSettings)
    #expect(ScreenGrab.settingsDecision(preflightGranted: true) == .none)
}

@Test func accessibilitySettingsDecision() {
    #expect(AccessibilityPermission.settingsDecision(trusted: false) == .request)
    #expect(AccessibilityPermission.settingsDecision(trusted: true) == .none)
}

@Test func accessibilityDoesNotPromptWhenTrusted() {
    #expect(!AccessibilityPermission.shouldPrompt(trusted: true))
    #expect(AccessibilityPermission.shouldPrompt(trusted: false))
}

@Test func windowCaptureNeedsAccessibilityWhenUntrusted() {
    #expect(ScreenGrab.requiresAccessibility(for: .window, trusted: false))
    #expect(!ScreenGrab.requiresAccessibility(for: .window, trusted: true))
    #expect(!ScreenGrab.requiresAccessibility(for: .screen, trusted: false))
    #expect(!ScreenGrab.requiresAccessibility(for: .screen, trusted: true))
}

@Test func accessibilityFailureCopyIsNotGenericRequestFailed() {
    #expect(SendFailureCopy.message(for: ScreenGrabError.accessibility) == HUDErrorLip.accessibilityPermission)
    #expect(SendFailureCopy.message(for: ScreenGrabError.accessibility) != "The request failed.")
    #expect(HUDErrorLip.accessibilityPermission != HUDErrorLip.screenPermission)
    #expect(HUDErrorLip.accessibilityPermission != HUDErrorLip.screenFailed)
}

@Test func captureHighlightSkipsUnknownFrame() {
    #expect(!CaptureHighlight.shouldShow(frame: nil))
    #expect(!CaptureHighlight.shouldShow(frame: .zero))
    #expect(!CaptureHighlight.shouldShow(frame: CGRect(x: 10, y: 10, width: 0, height: 40)))
    #expect(CaptureHighlight.shouldShow(frame: CGRect(x: 10, y: 20, width: 100, height: 80)))
}

@Test func captureHighlightDurationStaysReadableAndBrief() {
    #expect(CaptureHighlight.duration >= 0.5)
    #expect(CaptureHighlight.duration <= 1.5)
}

@Test func dictationGlowShowsOnlyWhileDictating() {
    #expect(IntelligenceGlowPolicy.showsDictationBorder(dictating: true))
    #expect(!IntelligenceGlowPolicy.showsDictationBorder(dictating: false))
}

@Test func listeningGlowPresetMatchesTunedValues() {
    let preset = IntelligenceGlowPreset.listening
    #expect(preset.variation == .overlay)
    #expect(preset.padding == 20)
    #expect(preset.lineWidthScale == 0.3)
    #expect(preset.blurScale == 1)
    #expect(preset.opacity == 0.3)
    #expect(preset.updateInterval == 0.4)
    #expect(preset.animationSpeed == 1)
    #expect(preset.blurRadius == 45)
    #expect(preset.sweepLineWidth == 1.6)
    #expect(preset.sweepSpan == 90)
    #expect(preset.sweepOffset == 220)
}

@Test func captureGlowPresetMatchesTunedValues() {
    let preset = IntelligenceGlowPreset.capture
    #expect(preset.variation == .glassBackground)
    #expect(preset.padding == 25.95)
    #expect(preset.lineWidthScale == 0.5)
    #expect(preset.blurScale == 2)
    #expect(preset.opacity == 0.6)
    #expect(preset.updateInterval == 0.4)
    #expect(preset.animationSpeed == 1)
    #expect(preset.blurRadius == 45)
    #expect(preset.sweepLineWidth == 4)
    #expect(preset.sweepSpan == 90)
    #expect(preset.sweepOffset == 220)
}

@Test func resolvedGlowSpecUsesPresetWithoutExtraScale() {
    let listening = IntelligenceGlowSpec.resolved(from: .listening)
    #expect(listening.padding == 20)
    #expect(listening.opacity == 0.3)
    #expect(listening.lineWidths == IntelligenceGlowSpec.baseLineWidths.map { $0 * 0.3 })
    #expect(listening.blurs == IntelligenceGlowSpec.baseBlurs.map { $0 * 1 })

    let capture = IntelligenceGlowSpec.resolved(from: .capture)
    #expect(capture.padding == 25.95)
    #expect(capture.opacity == 0.6)
    #expect(capture.lineWidths == IntelligenceGlowSpec.baseLineWidths.map { $0 * 0.5 })
    #expect(capture.blurs == IntelligenceGlowSpec.baseBlurs.map { $0 * 2 })
}

@Test func captureGlowDismissesWithOpacityOnly() {
    #expect(CaptureHighlight.edgeFadeDuration > 0)
    #expect(CaptureHighlight.edgeFadeDuration < CaptureHighlight.duration)
    #expect(CaptureHighlight.dismissesWithOpacityOnly)
    #expect(!CaptureHighlight.dismissesWithScaleOrInset)
}

@Test func captureGlowFlashesOnEveryScreenshotSend() {
    #expect(CaptureHighlight.shouldFlashOnSend(hasJPEG: true))
    #expect(CaptureHighlight.shouldFlashOnSend(hasJPEG: true))
    #expect(!CaptureHighlight.shouldFlashOnSend(hasJPEG: false))
}

@Test func screenCaptureFrameIsAValidHighlightTarget() {
    let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    #expect(CaptureHighlight.shouldShow(frame: display))
    let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(CaptureHighlight.shouldShow(frame: primary))
}

@Test func captureHighlightPanelInsetsTargetEvenlyInAppKitSpace() {
    let target = CGRect(x: 100, y: 200, width: 400, height: 300)
    let padding: CGFloat = 25.95
    let panel = CaptureHighlight.panelFrame(capturing: target, padding: padding)
    #expect(panel.origin.x == target.origin.x - padding)
    #expect(panel.origin.y == target.origin.y - padding)
    #expect(panel.width == target.width + padding * 2)
    #expect(panel.height == target.height + padding * 2)
    let insetBack = panel.insetBy(dx: padding, dy: padding)
    #expect(insetBack == target)
}

@Test func quartzCaptureRectConvertsToAppKitWithoutDownwardShiftBias() {
    let mainHeight: CGFloat = 1080
    // Top-of-screen window in Quartz (y near 0 from top).
    let quartz = CGRect(x: 120, y: 40, width: 800, height: 500)
    let appKit = CaptureHighlight.appKitRect(fromQuartz: quartz, mainDisplayHeight: mainHeight)
    #expect(appKit.origin.x == 120)
    #expect(appKit.width == 800)
    #expect(appKit.height == 500)
    // AppKit y grows up from the bottom of the main display.
    #expect(appKit.origin.y == mainHeight - 40 - 500)
    #expect(appKit.origin.y == 540)
    // Full primary display stays origin-aligned after conversion.
    let full = CaptureHighlight.appKitRect(
        fromQuartz: CGRect(x: 0, y: 0, width: 1920, height: mainHeight),
        mainDisplayHeight: mainHeight
    )
    #expect(full == CGRect(x: 0, y: 0, width: 1920, height: mainHeight))
    // Left display with negative Quartz X keeps X; Y still flips around main height.
    let left = CaptureHighlight.appKitRect(
        fromQuartz: CGRect(x: -1800, y: 100, width: 1800, height: 1169),
        mainDisplayHeight: mainHeight
    )
    #expect(left.origin.x == -1800)
    #expect(left.origin.y == mainHeight - 100 - 1169)
}

@Test func glowCornerRadiusMatchesHUDOrWindow() {
    #expect(IntelligenceGlowPolicy.cornerRadius(isHUD: true) == HUDMetrics.cornerRadius)
    #expect(IntelligenceGlowPolicy.cornerRadius(isHUD: true) == 24)
    #expect(IntelligenceGlowPolicy.cornerRadius(isHUD: false) == IntelligenceGlowPolicy.windowCornerRadius)
    #expect(IntelligenceGlowPolicy.windowCornerRadius >= 12)
    #expect(IntelligenceGlowPolicy.windowCornerRadius <= 16)
}

@Test func intelligenceGlowVariationDefaultsToOverlay() {
    #expect(IntelligenceGlowVariation.default == .overlay)
    #expect(IntelligenceGlowVariation.allCases.first == .overlay)
    #expect(IntelligenceGlowPreset.listening.variation == .overlay)
    #expect(IntelligenceGlowPreset.capture.variation == .glassBackground)
}

@Test func privacyPromptURLsMatchSystemPanes() {
    #expect(
        PrivacyPromptURL.microphone?.absoluteString
            == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
    )
    #expect(
        PrivacyPromptURL.speechRecognition?.absoluteString
            == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition"
    )
    #expect(
        PrivacyPromptURL.screenRecording?.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
    #expect(
        PrivacyPromptURL.accessibility?.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
}
