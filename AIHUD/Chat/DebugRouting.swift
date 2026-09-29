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
    case secondTurn = "second-turn"
    case armWindow = "arm-window"
    case multilineOn = "multiline-on"
    case multilineOff = "multiline-off"
    case historyOn = "history-on"
    case historyOff = "history-off"
    case missingEndpoint = "missing-endpoint"
    case missingKey = "missing-key"
    case missingModel = "missing-model"
    case signIn = "sign-in"
    case requestFailed = "request-failed"
    case streamSun = "stream-sun"
    case reply10 = "reply-10"
    case reply20 = "reply-20"
    case replyOverflow = "reply-overflow"
    case streamLine = "stream-line"
    case streamMulti = "stream-multi"
    case lowerExtension = "lower-extension"
    case upperExtension = "upper-extension"
    case expandedConversation = "expanded-conversation"
    case flashHighlight = "flash-highlight"
    case inFlightPrompt = "in-flight-prompt"
}

struct DebugLogoChoice: Equatable, Sendable, Identifiable {
    var title: String
    var command: String
    var kind: ProviderLogoKind

    var id: String { command }
}

struct DebugSnapshot: Equatable, Sendable {
    var session = Session()
    var captureArmed = false
    var dictating = false
    var voiceStatus: String?
    var screenNotice: String?
    var wantsCardKey: Bool?
    var logoOverride: ProviderLogoKind?
    var captureTargetOverride: CaptureTarget?
    var multilineOverride: Bool?
    var historyExpanded = false
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

enum HUDCardMenu {
    enum Item: Equatable, Sendable {
        case settings
        case debug
    }

    static func items(debugEnabled: Bool) -> [Item] {
        if debugEnabled {
            return [.settings, .debug]
        }
        return [.settings]
    }

    static func title(for item: Item) -> String {
        switch item {
        case .settings: return "Settings"
        case .debug: return "Debug"
        }
    }

    static func debugEnabled(arguments: [String], defaults: UserDefaults) -> Bool {
        DebugRouting.enabled(by: arguments) || DebugSettings.loadEnabled(from: defaults)
    }
}

struct DebugCommandPlan: Equatable, Sendable {
    var shimmer: InFlightShimmerStyle?
    var usePulsingOrb: Bool
    var kind: Kind

    enum Kind: Equatable, Sendable {
        case openTranscript
        case flashHighlight
        case liveStream(text: String, finish: Bool)
        case apply(DebugSnapshot)
    }
}

enum DebugRouting {
    static let draft = "What is the total mass of the sun?"
    static let partial = "The Sun's mass is about"
    static let reply = "The Sun's mass is about 1.989e30 kilograms."
    static let longReply = """
    Sure — here it is again.

    The Sun's total mass is about 1.989 × 10^30 kilograms. That's roughly 333,000 times Earth's mass, and about 99.86% of all the mass in the Solar System.

    In other units: about 2 × 10^30 kg, or roughly 2 octillion tonnes.
    """
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
    static let followUp = "And the Earth?"
    static let liveStreamReply =
        "back to the sun, huh? okay okay, here's the number: about 1.989 × 10^30 kilograms — roughly 333,000 earths, or 99.86% of everything in the solar system. same answer as last time, papi. it's not gonna change on us. what are you really digging at?"
    static let streamLineReply = "The Sun's mass is about 1.989e30 kilograms."
    static let streamMultiReply =
        "The Sun's total mass is about 1.989 × 10^30 kilograms. That's roughly 333,000 times Earth's mass, and about 99.86% of all the mass in the Solar System. In other units: about 2 × 10^30 kg, or roughly 2 octillion tonnes. Same number as last time; it is not going to change."
    static let missingKey = "Add an API key in Settings"
    static let missingModel = "Add a model id in Settings"
    static let signIn = "Sign in to ChatGPT in Settings"
    static let requestFailed = "The request failed."

    static func numberedReply(lines: Int) -> String {
        guard lines > 0 else { return "" }
        return (1...lines).map { "This is assistant reply line \($0)." }.joined(separator: "\n")
    }

    static func liveStreamText(for command: DebugCommand) -> String? {
        switch command {
        case .streamSun:
            return liveStreamReply
        case .replyOverflow:
            return numberedReply(lines: 40)
        case .streamLine:
            return streamLineReply
        case .streamMulti:
            return streamMultiReply
        default:
            return nil
        }
    }

    static func liveStreamFinishes(_ command: DebugCommand) -> Bool {
        switch command {
        case .streamLine, .streamMulti:
            return false
        default:
            return true
        }
    }

    /// One classification for a debug command. Unknown strings apply the current snapshot unchanged.
    static func plan(command: String, snapshot: DebugSnapshot) -> DebugCommandPlan {
        if command == "open-transcript" {
            return DebugCommandPlan(shimmer: nil, usePulsingOrb: false, kind: .openTranscript)
        }
        if let style = InFlightShimmerStyle.fromDebugCommand(command) {
            let next = apply(DebugCommand.inFlightPrompt.rawValue, to: snapshot)
            return DebugCommandPlan(shimmer: style, usePulsingOrb: true, kind: .apply(next))
        }
        let parsed = parse(command)
        if parsed == .flashHighlight {
            return DebugCommandPlan(shimmer: nil, usePulsingOrb: false, kind: .flashHighlight)
        }
        if let parsed, let text = liveStreamText(for: parsed) {
            return DebugCommandPlan(
                shimmer: nil,
                usePulsingOrb: false,
                kind: .liveStream(text: text, finish: liveStreamFinishes(parsed))
            )
        }
        return DebugCommandPlan(
            shimmer: nil,
            usePulsingOrb: parsed == .inFlightPrompt,
            kind: .apply(apply(command, to: snapshot))
        )
    }

    static let logoChoices: [DebugLogoChoice] = {
        var rows = [
            DebugLogoChoice(title: "On-device", command: "logo-on-device", kind: .appleIntelligence),
            DebugLogoChoice(title: "Axiom", command: "logo-axiom", kind: .axiom)
        ]
        for preset in ChatEndpointCatalog.cloudPresets {
            rows.append(
                DebugLogoChoice(
                    title: preset.name,
                    command: logoCommand(forPreset: preset.id),
                    kind: HUDModelMenu.logo(forPresetID: preset.id)
                )
            )
        }
        return rows
    }()

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

    static func logoKind(from command: String) -> ProviderLogoKind? {
        guard command.hasPrefix("logo-") else { return nil }
        let slug = String(command.dropFirst("logo-".count))
        if slug == "chatgpt" {
            return .openai
        }
        if slug == "on-device" || slug == "apple" {
            return .appleIntelligence
        }
        return ProviderLogoKind(rawValue: slug)
    }

    static func logoCommand(forPreset id: String) -> String {
        switch id {
        case "alibaba_cloud": return "logo-alibaba"
        case "chatgpt": return "logo-chatgpt"
        default: return "logo-\(id)"
        }
    }

    static func phase(for command: String) -> Phase? {
        switch parse(command) {
        case .composingEmpty, .composingDraft, .reset:
            return .composing
        case .waiting, .inFlightPrompt:
            return .waiting
        case .streaming, .streamLine, .streamMulti:
            return .streaming
        case .finished, .markdownReply, .secondTurn, .streamSun, .reply10, .reply20, .replyOverflow,
             .lowerExtension, .upperExtension, .expandedConversation:
            return .finished
        case .failed:
            return .failed(timedOut)
        case .missingEndpoint:
            return .failed(ChatEndpointCatalog.missingEndpointMessage)
        case .missingKey:
            return .failed(missingKey)
        case .missingModel:
            return .failed(missingModel)
        case .signIn:
            return .failed(signIn)
        case .requestFailed:
            return .failed(requestFailed)
        case .none, .ask, .agent, .armScreen, .disarmScreen, .dictateOn, .dictateOff,
             .addChip, .micDenied, .speechDenied, .genericFailure, .clearStatus, .makeKey, .resignKey,
             .armWindow, .multilineOn, .multilineOff, .historyOn, .historyOff, .flashHighlight:
            return nil
        }
    }

    static func apply(_ command: String, to session: Session) -> Session {
        apply(command, to: DebugSnapshot(session: session)).session
    }

    static func apply(_ command: String, to snapshot: DebugSnapshot) -> DebugSnapshot {
        if let kind = logoKind(from: command) {
            var next = snapshot
            next.wantsCardKey = nil
            next.logoOverride = kind
            return next
        }
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
        case .inFlightPrompt:
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
            next.session = failed(timedOut)
            clearStatus(&next)
        case .reset:
            next = DebugSnapshot()
        case .ask:
            next.session.preset = .ask
        case .agent:
            next.session.preset = .agent
        case .armScreen:
            next.captureArmed = true
            next.captureTargetOverride = .screen
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
        case .secondTurn:
            next.session = secondTurnSession()
            clearStatus(&next)
        case .armWindow:
            next.captureArmed = true
            next.captureTargetOverride = .window
        case .multilineOn:
            next.multilineOverride = true
        case .multilineOff:
            next.multilineOverride = false
        case .historyOn:
            next.historyExpanded = true
        case .historyOff:
            next.historyExpanded = false
        case .missingEndpoint:
            next.session = failed(ChatEndpointCatalog.missingEndpointMessage)
            clearStatus(&next)
        case .missingKey:
            next.session = failed(missingKey)
            clearStatus(&next)
        case .missingModel:
            next.session = failed(missingModel)
            clearStatus(&next)
        case .signIn:
            next.session = failed(signIn)
            clearStatus(&next)
        case .requestFailed:
            next.session = failed(requestFailed)
            clearStatus(&next)
        case .streamSun:
            next.session = replayed(text: liveStreamReply, finish: true)
            clearStatus(&next)
        case .reply10:
            next.session = numberedFinished(lines: 10)
            clearStatus(&next)
        case .reply20:
            next.session = numberedFinished(lines: 20)
            clearStatus(&next)
        case .replyOverflow:
            next.session = replayed(text: numberedReply(lines: 40), finish: true)
            clearStatus(&next)
        case .streamLine:
            next.session = replayed(text: streamLineReply, finish: false)
            clearStatus(&next)
        case .streamMulti:
            next.session = replayed(text: streamMultiReply, finish: false)
            clearStatus(&next)
        case .lowerExtension:
            next.session = numberedFinished(lines: 15)
            clearStatus(&next)
        case .upperExtension:
            next.session = numberedFinished(lines: 30)
            clearStatus(&next)
        case .expandedConversation:
            next.session = longExpandedConversation()
            next.historyExpanded = true
            clearStatus(&next)
        case .flashHighlight:
            break
        }
        return next
    }

    static func streamChunks(_ text: String, size: Int = 28) -> [String] {
        guard size > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[index..<end]))
            index = end
        }
        return chunks
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
        session.draft = draft
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
        session.draft = ""
        session.phase = .finished
        return session
    }

    private static func markdownFinished() -> Session {
        var session = waiting()
        session.displayAnswer = markdownReply
        session.turns.append(Turn(role: .assistant, text: markdownReply, chips: []))
        session.draft = ""
        session.phase = .finished
        return session
    }

    private static func numberedFinished(lines: Int) -> Session {
        var session = waiting()
        let text = numberedReply(lines: lines)
        session.displayAnswer = text
        session.turns.append(Turn(role: .assistant, text: text, chips: []))
        session.draft = ""
        session.phase = .finished
        return session
    }

    /// Several turns that unroll past the 30-line height cap when history is expanded.
    private static func longExpandedConversation() -> Session {
        var session = Session()
        session.startedAt = Date()
        let exchanges: [(String, String)] = [
            (
                "What is the mass of the Sun?",
                numberedReply(lines: 12)
            ),
            (
                "And how does that compare to Earth?",
                numberedReply(lines: 12)
            ),
            (
                "Walk me through the Solar System mass budget.",
                numberedReply(lines: 16)
            ),
            (
                "Give me a longer wrap-up I can scroll through.",
                numberedReply(lines: 20)
            )
        ]
        var turns: [Turn] = []
        for (user, assistant) in exchanges {
            turns.append(Turn(role: .user, text: user, chips: []))
            turns.append(Turn(role: .assistant, text: assistant, chips: []))
        }
        session.turns = turns
        session.displayAnswer = exchanges.last?.1 ?? ""
        session.draft = ""
        session.phase = .finished
        return session
    }

    private static func replayed(text: String, finish: Bool) -> Session {
        var session = waiting()
        for chunk in streamChunks(text) {
            session.receiveToken(chunk)
        }
        if finish {
            session.finish()
        }
        return session
    }

    private static func secondTurnSession() -> Session {
        var session = waiting()
        session.displayAnswer = longReply
        session.turns.append(Turn(role: .assistant, text: longReply, chips: []))
        session.phase = .finished
        session.draft = followUp
        return session
    }

    private static func failed(_ message: String) -> Session {
        var session = Session()
        session.draft = draft
        session.errorMessage = message
        session.phase = .failed(message)
        return session
    }
}

enum DebugChatApply {
    static func readyPick(
        logo: ProviderLogoKind,
        endpoints: [ChatEndpoint],
        current: ChatModelSelection,
        secret: (UUID) -> String,
        onDeviceReady: Bool = true
    ) -> ChatModelSelection? {
        let items = HUDModelMenu.items(
            endpoints: endpoints,
            chatID: current.chatID,
            chatModelID: current.chatModelID,
            secret: secret,
            onDeviceReady: onDeviceReady
        )
        for item in items {
            guard let endpoint = endpoints.first(where: { $0.id == item.providerID }) else {
                continue
            }
            guard HUDModelMenu.logo(for: endpoint) == logo else { continue }
            guard let model = item.models.first(where: \.enabled) else { continue }
            return HUDModelMenu.selecting(
                providerID: item.providerID,
                modelID: model.id,
                in: current
            )
        }
        return nil
    }
}
