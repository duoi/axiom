import Foundation

enum DebugCommand: String, Equatable, Sendable, CaseIterable {
    case composingEmpty = "composing-empty"
    case composingDraft = "composing-draft"
    case waiting
    case streaming
    case finished
    case failed
    case reset
    case ask
    case agent
    case armScreen = "arm-screen"
    case disarmScreen = "disarm-screen"
    case dictateOn = "dictate-on"
    case dictateOff = "dictate-off"
    case addChip = "add-chip"
    case micDenied = "mic-denied"
    case speechDenied = "speech-denied"
    case genericFailure = "generic-failure"
    case clearStatus = "clear-status"
    case makeKey = "make-key"
    case resignKey = "resign-key"
    case markdownReply = "markdown-reply"
}

struct DebugSnapshot: Equatable, Sendable {
    var session = Session()
    var captureArmed = false
    var dictating = false
    var voiceStatus: String?
    var screenNotice: String?
    var wantsCardKey: Bool?
}

enum DebugSettings {
    static let enabledKey = "debug.enabled"

    static func loadEnabled(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: enabledKey)
    }
}

enum DebugRouting {
    static let draft = "What is the total mass of the sun?"
    static let partial = "The Sun's mass is about"
    static let reply = "The Sun's mass is about 1.989e30 kilograms."
    static let markdownReply = #"""
Here is a short plan:

- First
- Second

```swift
func greet() {
    print("hello")
}
```
"""#
    static let timedOut = "The request timed out."
    static let genericFailure = "The screen capture failed."
    static let chipName = "notes.txt"

    static func enabled(by arguments: [String]) -> Bool {
        arguments.contains("--debug")
    }

    static func initialCommand(from arguments: [String]) -> String? {
        if let paired = arguments.first(where: { $0.hasPrefix("--debug-state=") }) {
            let value = String(paired.dropFirst("--debug-state=".count))
            return value.isEmpty ? nil : value
        }
        if let index = arguments.firstIndex(of: "--debug-state"),
           arguments.indices.contains(index + 1)
        {
            let value = arguments[index + 1]
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func parse(_ command: String) -> DebugCommand? {
        DebugCommand(rawValue: command)
    }

    static func phase(for command: String) -> Phase? {
        switch parse(command) {
        case .composingEmpty, .composingDraft, .reset:
            return .composing
        case .waiting:
            return .waiting
        case .streaming:
            return .streaming
        case .finished, .markdownReply:
            return .finished
        case .failed:
            return .failed(timedOut)
        case .none, .ask, .agent, .armScreen, .disarmScreen, .dictateOn, .dictateOff,
             .addChip, .micDenied, .speechDenied, .genericFailure, .clearStatus, .makeKey, .resignKey:
            return nil
        }
    }

    static func apply(_ command: String, to session: Session) -> Session {
        apply(command, to: DebugSnapshot(session: session)).session
    }

    static func apply(_ command: String, to snapshot: DebugSnapshot) -> DebugSnapshot {
        guard let parsed = parse(command) else { return snapshot }
        return apply(parsed, to: snapshot)
    }

    static func apply(_ command: DebugCommand, to snapshot: DebugSnapshot) -> DebugSnapshot {
        var next = snapshot
        next.wantsCardKey = nil
        switch command {
        case .composingEmpty:
            next.session = composing(draft: "")
            clearStatus(&next)
        case .composingDraft:
            next.session = composing(draft: draft)
            clearStatus(&next)
        case .waiting:
            next.session = waiting()
            clearStatus(&next)
        case .streaming:
            next.session = streaming()
            clearStatus(&next)
        case .finished:
            next.session = finished()
            clearStatus(&next)
        case .markdownReply:
            next.session = markdownFinished()
            clearStatus(&next)
        case .failed:
            next.session = failed()
            clearStatus(&next)
        case .reset:
            next = DebugSnapshot()
        case .ask:
            next.session.preset = .ask
        case .agent:
            next.session.preset = .agent
        case .armScreen:
            next.captureArmed = true
        case .disarmScreen:
            next.captureArmed = false
        case .dictateOn:
            next.dictating = true
        case .dictateOff:
            next.dictating = false
        case .addChip:
            if !next.session.chips.contains(where: { $0.name == chipName }) {
                next.session.chips.append(Chip(id: UUID(), name: chipName, payload: .text("Sample context")))
            }
            next.session.errorMessage = nil
            if case .failed = next.session.phase {
                next.session.phase = .composing
            }
        case .micDenied:
            next.voiceStatus = VoiceStatusCopy.micDenied
        case .speechDenied:
            next.voiceStatus = VoiceStatusCopy.speechDenied
        case .genericFailure:
            next.screenNotice = genericFailure
        case .clearStatus:
            next.voiceStatus = nil
            next.screenNotice = nil
        case .makeKey:
            next.wantsCardKey = true
        case .resignKey:
            next.wantsCardKey = false
        }
        return next
    }

    private static func clearStatus(_ snapshot: inout DebugSnapshot) {
        snapshot.voiceStatus = nil
        snapshot.screenNotice = nil
    }

    private static func composing(draft: String) -> Session {
        var session = Session()
        session.draft = draft
        session.phase = .composing
        return session
    }

    private static func waiting() -> Session {
        var session = Session()
        session.startedAt = Date()
        session.turns = [Turn(role: .user, text: draft, chips: [])]
        session.phase = .waiting
        return session
    }

    private static func streaming() -> Session {
        var session = waiting()
        session.displayAnswer = partial
        session.phase = .streaming
        return session
    }

    private static func finished() -> Session {
        var session = streaming()
        session.displayAnswer = reply
        session.turns.append(Turn(role: .assistant, text: reply, chips: []))
        session.phase = .finished
        return session
    }

    private static func markdownFinished() -> Session {
        var session = waiting()
        session.displayAnswer = markdownReply
        session.turns.append(Turn(role: .assistant, text: markdownReply, chips: []))
        session.phase = .finished
        return session
    }

    private static func failed() -> Session {
        var session = Session()
        session.draft = draft
        session.errorMessage = timedOut
        session.phase = .failed(timedOut)
        return session
    }
}
