import SwiftUI

/// Session-only debug knobs for shimmer, the send orb, and intelligence glow.
/// The card reads `cardOrb`, which stays on the production default until debug is on.
@MainActor
@Observable
final class DebugPreviewStore {
    static let shared = DebugPreviewStore()

    var shimmerStyle: InFlightShimmerStyle = .default {
        didSet { refreshResolvedCard() }
    }

    var orbChoice: ThinkingOrbChoice = .production {
        didSet { refreshResolvedCard() }
    }

    private(set) var debugEnabled = false
    private(set) var cardOrb: ThinkingOrbChoice = .production

    /// Which preset the sliders edit and Listening vs Flash should load.
    var activeContext: IntelligenceGlowContext = .listening
    /// Session overrides. Reset restores the factory preset for the active context.
    var listening = IntelligenceGlowPreset.listening
    var capture = IntelligenceGlowPreset.capture

    var onChange: (() -> Void)?

    var activePreset: IntelligenceGlowPreset {
        get {
            switch activeContext {
            case .listening: listening
            case .capture: capture
            }
        }
        set {
            switch activeContext {
            case .listening: listening = newValue
            case .capture: capture = newValue
            }
        }
    }

    func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        refreshResolvedCard()
    }

    func activate(_ context: IntelligenceGlowContext, notify notifyChange: Bool = true) {
        activeContext = context
        if notifyChange {
            notify()
        }
    }

    func resetActivePreset() {
        activePreset = IntelligenceGlowPreset.factory(activeContext)
        notify()
    }

    func resetBothPresets() {
        listening = .listening
        capture = .capture
        notify()
    }

    func notify() {
        onChange?()
    }

    func resolvedSpec(for context: IntelligenceGlowContext) -> IntelligenceGlowSpec {
        let preset: IntelligenceGlowPreset
        switch context {
        case .listening: preset = listening
        case .capture: preset = capture
        }
        return .resolved(from: preset)
    }

    func variation(for context: IntelligenceGlowContext) -> IntelligenceGlowVariation {
        switch context {
        case .listening: listening.variation
        case .capture: capture.variation
        }
    }

    private func refreshResolvedCard() {
        cardOrb = debugEnabled ? orbChoice : .production
    }
}
