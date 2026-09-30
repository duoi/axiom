import Foundation

/// When the Composing orb replaces the send icon.
enum ReplyWaitingChrome {
    static func showsComposingOrb(phase: Phase, answer: String) -> Bool {
        answer.isEmpty && (phase == .waiting || phase == .streaming)
    }
}

/// Reply band and expand chevron. Waiting with no text stays compact.
enum HistoryChromePolicy {
    static func showsReplyRegion(
        answer: String,
        phase: Phase,
        historyExpanded: Bool
    ) -> Bool {
        if historyExpanded { return true }
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if case .failed = phase { return true }
        return false
    }

    static func showsExpandChevron(
        answer: String,
        phase: Phase,
        historyExpanded: Bool,
        hasUserTurns: Bool
    ) -> Bool {
        guard hasUserTurns else { return false }
        return showsReplyRegion(answer: answer, phase: phase, historyExpanded: historyExpanded)
    }
}

/// Prompt field while a turn is in flight: keep the submitted string, lock editing.
enum PromptInFlightPolicy {
    static func isInFlight(_ phase: Phase) -> Bool {
        phase == .waiting || phase == .streaming
    }

    static func isEditable(phase: Phase) -> Bool {
        !isInFlight(phase)
    }

    static func promptDraft(whileSending submitted: String) -> String {
        submitted
    }

    static func promptDraftAfterSuccess() -> String {
        ""
    }

    static func promptDraftAfterFailure(submitted: String) -> String {
        submitted
    }

}
