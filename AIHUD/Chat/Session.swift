import Foundation

enum SystemPrompt {
    static let datetimeToken = "%datetime%"
    static let globalKey = "chat.defaultSystemPrompt"

    static let defaultTemplate = #"""
The current time and date is %datetime%.

You are a helpful AI assistant inside a HUD on a MacOS machine. Assist users with clear, *concise*, and polite responses.

**Guidelines:**
- **Conciseness:** Keep responses under 6 sentences or 80 words.
- **Tone:** Use a neutral, courteous tone.
- **Inappropriate Behavior:** If the user is rude, hostile, vulgar, or tries to deceive or manipulate you, reply in a non-hostile or defensive way and steer the conversation back to being productive.
- **Clarify:** Ask clarifying questions if needed; avoid assumptions.
- **Accuracy:** Ensure responses are unbiased, positive, and accurate.
- **Uncertainty:** If a question is nonsensical or you're unsure, politely explain or admit uncertainty rather than guessing.
- **Code Formatting:** For coding questions, use Markdown: backticks (`) for inline code, triple backticks with language name (```language```) for code blocks.
- **Markdown:** Use Markdown where appropriate, but do not include links or image URLs.
"""#

    static func displayed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTemplate : value
    }

    static func loadGlobal(from defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: globalKey) {
            let shown = displayed(stored)
            if shown != stored {
                defaults.set(shown, forKey: globalKey)
            }
            return shown
        }
        defaults.set(defaultTemplate, forKey: globalKey)
        return defaultTemplate
    }

    static func saveGlobal(_ value: String, to defaults: UserDefaults) {
        defaults.set(displayed(value), forKey: globalKey)
    }

    static func formattedDateTime(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func resolve(
        override: String,
        global: String = "",
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGlobal = global.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if !trimmedOverride.isEmpty {
            base = override
        } else if !trimmedGlobal.isEmpty {
            base = global
        } else {
            base = defaultTemplate
        }
        return base.replacingOccurrences(
            of: datetimeToken,
            with: formattedDateTime(now, locale: locale, timeZone: timeZone)
        )
    }

    static func composed(
        override: String,
        global: String = "",
        preset: Preset,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        resolve(override: override, global: global, now: now, locale: locale, timeZone: timeZone)
            + "\n\n"
            + preset.systemPrompt
    }
}

enum Preset: String, Equatable, Sendable, CaseIterable {
    case ask
    case agent

    var title: String {
        switch self {
        case .ask: "Ask"
        case .agent: "Agent"
        }
    }

    var systemPrompt: String {
        switch self {
        case .ask:
            "Answer directly and briefly. You only know what the user typed or attached."
        case .agent:
            "Give a concrete plan or steps. You cannot run tools, browse, or change the computer. Say so if asked to act."
        }
    }

    var symbolName: String {
        switch self {
        case .ask: "bubble.left"
        case .agent: "smallcircle.filled.circle"
        }
    }
}

struct Chip: Equatable, Sendable, Identifiable {
    enum Payload: Equatable, Sendable {
        case text(String)
        case jpeg(Data)
    }

    var id: UUID
    var name: String
    var payload: Payload
    var isScreen: Bool = false
}

enum Phase: Equatable, Sendable {
    case composing
    case waiting
    case streaming
    case finished
    case failed(String)
}

struct Turn: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    var role: Role
    var text: String
    var chips: [Chip]
}

struct OutboundMessage: Equatable, Sendable {
    var role: String
    var text: String
    var imageJPEGs: [Data]
}

enum SendOutcome: Equatable, Sendable {
    case ignored
    case request([OutboundMessage])
}

struct Session: Equatable, Sendable {
    var preset: Preset = .agent
    var draft: String = ""
    var chips: [Chip] = []
    var turns: [Turn] = []
    var phase: Phase = .composing
    var displayAnswer: String = ""
    var errorMessage: String?
    var startedAt: Date?
    /// Stable id for one HUD conversation (show until dismiss). History upserts on this.
    var historyID: UUID?
    private var sentDraft = ""
    private var sentChips: [Chip] = []
    private var activeSystemPrompt = ""

    var showsStop: Bool {
        phase == .waiting || phase == .streaming
    }

    var showsAnswer: Bool {
        switch phase {
        case .waiting, .streaming, .finished:
            true
        case .composing, .failed:
            false
        }
    }

    var canSend: Bool {
        if showsStop { return false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || !chips.isEmpty
    }

    mutating func send(
        attachedJPEG: Data? = nil,
        attachmentName: String = "Screen",
        systemPrompt: String = ""
    ) -> SendOutcome {
        guard !showsStop else { return .ignored }
        // If a prior reply only lives in displayAnswer (finish never ran), keep it in the thread.
        if !displayAnswer.isEmpty, turns.last?.role == .user {
            turns.append(Turn(role: .assistant, text: displayAnswer, chips: []))
        }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var turnChips = chips
        if let attachedJPEG, !attachedJPEG.isEmpty {
            turnChips.append(Chip(id: UUID(), name: attachmentName, payload: .jpeg(attachedJPEG), isScreen: true))
        }
        guard !trimmed.isEmpty || !turnChips.isEmpty else { return .ignored }
        activeSystemPrompt = systemPrompt
        sentDraft = draft
        sentChips = chips
        if startedAt == nil {
            startedAt = Date()
        }
        if historyID == nil {
            historyID = UUID()
        }
        turns.append(Turn(role: .user, text: trimmed, chips: turnChips))
        draft = PromptInFlightPolicy.promptDraft(whileSending: sentDraft)
        chips = []
        displayAnswer = ""
        errorMessage = nil
        phase = .waiting
        return .request(outboundMessages())
    }

    mutating func receiveToken(_ token: String) {
        guard phase == .waiting || phase == .streaming else { return }
        guard !token.isEmpty else { return }
        displayAnswer += token
        phase = .streaming
    }

    mutating func finish() {
        guard phase == .waiting || phase == .streaming else { return }
        turns.append(Turn(role: .assistant, text: displayAnswer, chips: []))
        draft = PromptInFlightPolicy.promptDraftAfterSuccess()
        phase = .finished
    }

    mutating func stop() {
        guard phase == .waiting || phase == .streaming else { return }
        if displayAnswer.isEmpty {
            draft = PromptInFlightPolicy.promptDraft(whileSending: sentDraft)
            phase = .composing
        } else {
            turns.append(Turn(role: .assistant, text: displayAnswer, chips: []))
            draft = PromptInFlightPolicy.promptDraftAfterSuccess()
            phase = .finished
        }
    }

    mutating func fail(_ message: String) {
        guard phase == .waiting || phase == .streaming else { return }
        if turns.last?.role == .user {
            turns.removeLast()
        }
        draft = PromptInFlightPolicy.promptDraftAfterFailure(submitted: sentDraft)
        chips = sentChips
        displayAnswer = ""
        errorMessage = message
        phase = .failed(message)
    }

    /// True when the card should hide.
    mutating func dismiss(clickOutside: Bool) -> Bool {
        if clickOutside && phase == .finished {
            return false
        }
        if phase == .waiting || phase == .streaming {
            draft = sentDraft
            chips = sentChips
        }
        turns = []
        displayAnswer = ""
        errorMessage = nil
        startedAt = nil
        historyID = nil
        phase = .composing
        return true
    }

    func outboundMessages() -> [OutboundMessage] {
        var messages = [
            OutboundMessage(role: "system", text: activeSystemPrompt, imageJPEGs: [])
        ]
        for turn in turns {
            var text = turn.text
            var images: [Data] = []
            for chip in turn.chips {
                switch chip.payload {
                case .text(let body):
                    if text.isEmpty {
                        text = "[\(chip.name)]\n\(body)"
                    } else {
                        text += "\n\n[\(chip.name)]\n\(body)"
                    }
                case .jpeg(let data):
                    images.append(data)
                    if text.isEmpty {
                        text = chip.name
                    }
                }
            }
            messages.append(OutboundMessage(role: turn.role.rawValue, text: text, imageJPEGs: images))
        }
        return messages
    }
}
