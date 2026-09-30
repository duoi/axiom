import Foundation

/// Shared chat option for reasoning / thinking effort across providers.
enum ReasoningEffort: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// OpenAI/Responses send `"none"`; Anthropic omits `thinking`.
    case none
    case minimal
    case low
    case medium
    case high

    static let defaultsKey = "chat.reasoningEffort"
    static let `default`: ReasoningEffort = .medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// OpenAI chat completions `reasoning_effort` / Responses `reasoning.effort`.
    /// Always a concrete value, including `"none"`.
    var openAIValue: String { rawValue }

    /// Anthropic extended-thinking token budget. Nil for None.
    var anthropicBudgetTokens: Int? {
        switch self {
        case .none: nil
        case .minimal: 1_024
        case .low: 2_048
        case .medium: 8_192
        case .high: 16_384
        }
    }

    static func load(from defaults: UserDefaults) -> ReasoningEffort {
        guard let raw = defaults.string(forKey: defaultsKey) else {
            return .default
        }
        if raw == "off" { return .none }
        return ReasoningEffort(rawValue: raw) ?? .default
    }

    static func save(_ value: ReasoningEffort, to defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: defaultsKey)
    }
}
