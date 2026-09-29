import Foundation

enum VoiceSettings {
    static let wakeOnAxiomKey = "voice.wakeOnAxiom"
    static let pauseToSendKey = "voice.pauseToSend"

    static func loadWakeOnAxiom(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: wakeOnAxiomKey)
    }

    static func saveWakeOnAxiom(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: wakeOnAxiomKey)
    }

    static func loadPauseToSend(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: pauseToSendKey)
    }

    static func savePauseToSend(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: pauseToSendKey)
    }
}

enum VoiceStatusCopy {
    static let micDenied = "Allow the microphone in System Settings."
    static let speechDenied = "Allow speech recognition in System Settings."
    static let adHocPermission = "An ad-hoc rebuild can forget the microphone permission until you allow it again."
    static let missingModel = "The speech model is not installed."
    static let unsupportedModel = "This Mac does not support the speech model."
    static let downloading = "The speech model is still downloading."
    static let captureFailed = "The microphone capture failed."

    static func systemSettingsURL(for status: String) -> URL? {
        switch status {
        case micDenied:
            return PrivacyPromptURL.microphone
        case speechDenied:
            return PrivacyPromptURL.speechRecognition
        default:
            return nil
        }
    }
}

enum VoiceParser {
    static let silenceBuffer: TimeInterval = 2
    static let emptyWakeHideAfter: TimeInterval = 4
    static let cooldown: TimeInterval = 1.2

    struct Wake: Equatable, Sendable {
        var remainder: String
    }

    static func wake(in finalized: String) -> Wake? {
        let trimmed = finalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "^(?:hey\\s+)?axiom\\b", options: [.caseInsensitive]) else {
            return nil
        }
        let full = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: full),
              let matched = Range(match.range, in: trimmed)
        else {
            return nil
        }
        let remainder = trimmedLeadingPunctuation(String(trimmed[matched.upperBound...]))
        return Wake(remainder: remainder)
    }

    private static func trimmedLeadingPunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, first.isPunctuation {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func draftText(from recognized: String) -> String {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wake = wake(in: trimmed) {
            return wake.remainder
        }
        return trimmed
    }

    static func join(_ base: String, _ tail: String) -> String {
        let left = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        if left.hasSuffix(" ") || right.hasPrefix(" ") {
            return left + right
        }
        return left + " " + right
    }

    static func applyTranscript(base: String, transcript: String, isFinal: Bool) -> (base: String, display: String) {
        let display = join(base, transcript)
        if isFinal {
            return (base: display, display: display)
        }
        return (base: base, display: display)
    }

    static func shouldAutoSend(
        optionOn: Bool,
        draft: String,
        silentFor: TimeInterval,
        phase: Phase,
        dictating: Bool
    ) -> Bool {
        guard optionOn, dictating else { return false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard silentFor >= silenceBuffer else { return false }
        switch phase {
        case .waiting, .streaming:
            return false
        case .composing, .finished, .failed:
            return true
        }
    }

    static func cooldownBlocks(lastWake: Date?, now: Date) -> Bool {
        guard let lastWake else { return false }
        return now.timeIntervalSince(lastWake) < cooldown
    }

    static func shouldHideEmptyWake(
        openedFromWake: Bool,
        draft: String,
        openedAt: Date,
        now: Date
    ) -> Bool {
        guard openedFromWake else { return false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty else { return false }
        return now.timeIntervalSince(openedAt) >= emptyWakeHideAfter
    }
}
