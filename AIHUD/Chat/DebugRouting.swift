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
    static let followUp = "And the Earth?"
    static let missingKey = "Add an API key in Settings"
    static let missingModel = "Add a model id in Settings"
    static let signIn = "Sign in to ChatGPT in Settings"
    static let requestFailed = "The request failed."

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
        case .waiting:
            return .waiting
        case .streaming:
            return .streaming
        case .finished, .markdownReply, .secondTurn:
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
             .armWindow, .multilineOn, .multilineOff, .historyOn, .historyOff:
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

    private static func secondTurnSession() -> Session {
        var session = finished()
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
