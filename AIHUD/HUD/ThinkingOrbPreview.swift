import SwiftUI
import ThinkingOrbs

/// Debug picker values: stock ThinkingOrbs, glow-tinted twins, and Pulsing orb.
enum ThinkingOrbChoice: String, CaseIterable, Identifiable, Sendable {
    case working
    case searching
    case solving
    case listening
    case connecting
    case weaving
    case composing
    case breathing
    case shaping
    case workingGlow
    case searchingGlow
    case solvingGlow
    case listeningGlow
    case connectingGlow
    case weavingGlow
    case composingGlow
    case breathingGlow
    case shapingGlow
    case pulsingOrb

    var id: String { rawValue }

    var design: OrbDesign? {
        switch self {
        case .working, .workingGlow: .working
        case .searching, .searchingGlow: .searching
        case .solving, .solvingGlow: .solving
        case .listening, .listeningGlow: .listening
        case .connecting, .connectingGlow: .connecting
        case .weaving, .weavingGlow: .weaving
        case .composing, .composingGlow: .composing
        case .breathing, .breathingGlow: .breathing
        case .shaping, .shapingGlow: .shaping
        case .pulsingOrb: nil
        }
    }

    var usesGlow: Bool {
        switch self {
        case .workingGlow, .searchingGlow, .solvingGlow, .listeningGlow,
             .connectingGlow, .weavingGlow, .composingGlow, .breathingGlow, .shapingGlow:
            true
        default:
            false
        }
    }

    var usesPulsingOrb: Bool { self == .pulsingOrb }

    var title: String {
        if usesPulsingOrb { return String(localized: "Pulsing orb") }
        guard let design else { return rawValue }
        return usesGlow ? String(localized: "\(design.title) glow") : design.title
    }

    var summary: String {
        if usesPulsingOrb {
            return String(localized: "Blue-purple rings from AI-Animation-Demo. Debug send icon only.")
        }
        guard let design else { return "" }
        return usesGlow
            ? String(localized: "\(design.summary). Conic intelligence palette on the dots.")
            : design.summary
    }

    static let production: ThinkingOrbChoice = .composing
}

/// ThinkingOrbs pause TimelineView when scenePhase is background. Accessory HUD
/// panels stay nonactivating, so SwiftUI reports background and the orb freezes
/// on one frame. Force active scene phase and drive our own unpaused clock.
struct AnimatedThinkingOrb: View {
    var choice: ThinkingOrbChoice
    var diameter: CGFloat = HUDMetrics.controlSize

    var body: some View {
        Group {
            if choice.usesPulsingOrb {
                PulsingOrbIndicator(diameter: diameter)
            } else if let design = choice.design {
                thinkingOrb(design: design)
            }
        }
        .accessibilityLabel(Text(choice.title))
    }

    @ViewBuilder
    private func thinkingOrb(design: OrbDesign) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.6) / 2.6 * 360
            ZStack {
                ThinkingOrb(design, size: .small, diameter: diameter)
                    .environment(\.scenePhase, .active)
                    .environment(\.colorScheme, .dark)
                if choice.usesGlow {
                    AngularGradient(
                        colors: [Color].intelligenceColors + [[Color].intelligenceColors[0]],
                        center: .center,
                        angle: .degrees(angle)
                    )
                    .blendMode(.color)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: diameter, height: diameter)
            .compositingGroup()
        }
    }
}
