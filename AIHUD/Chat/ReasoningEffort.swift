import Foundation

/// Shared chat option for reasoning / thinking effort across providers.
enum ReasoningEffort: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// OpenAI/Responses send `"off"`; Anthropic omits `thinking`.
    case off
    case minimal
    case low
    case medium
    case high

    static let defaultsKey = "chat.reasoningEffort"
    static let `default`: ReasoningEffort = .off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// OpenAI chat completions `reasoning_effort` / Responses `reasoning.effort`.
    /// Always a concrete value, including `"off"`.
    var openAIValue: String { rawValue }

    /// Anthropic extended-thinking token budget when effort is on. Nil for Off.
    var anthropicBudgetTokens: Int? {
        switch self {
        case .off: nil
        case .minimal: 1_024
        case .low: 2_048
        case .medium: 8_192
        case .high: 16_384
        }
    }

    static func load(from defaults: UserDefaults) -> ReasoningEffort {
        guard let raw = defaults.string(forKey: defaultsKey),
              let value = ReasoningEffort(rawValue: raw)
        else {
            return .default
        }
        return value
    }

    static func save(_ value: ReasoningEffort, to defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: defaultsKey)
    }
}
