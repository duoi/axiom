import SwiftUI

/// Text shimmer presets from mdo91/AI-Animation-Demo. Names match the demo's
/// AnimationKind labels. Analyzing the text and Sequential dot grid are not
/// text shimmers (orb / grid) and are omitted here.
enum InFlightShimmerStyle: String, CaseIterable, Identifiable, Sendable {
    case chatGPTStyle = "chatgpt"
    case grokStyle = "grok"
    case shimmeringText = "shimmering-text"
    case summerizingTheText = "summerizing-the-text"
    case processingLabel = "processing-label"

    static let `default`: InFlightShimmerStyle = .chatGPTStyle

    var id: String { rawValue }

    /// Labels from AI-Animation-Demo AnimationKind.
    var title: String {
        switch self {
        case .chatGPTStyle: "ChatGPT style"
        case .grokStyle: "Grok style"
        case .shimmeringText: "ShimmeringText"
        case .summerizingTheText: "Summerizing the text"
        case .processingLabel: "Processing label"
        }
    }

    var summary: String {
        switch self {
        case .chatGPTStyle:
            "Monochrome gray gradient sweep."
        case .grokStyle:
            "Blue to purple to pink on bold text."
        case .shimmeringText:
            "Base colorful gradient fill."
        case .summerizingTheText:
            "Secondary text with a soft highlight and a short pause."
        case .processingLabel:
            "Secondary text with a continuous highlight sweep."
        }
    }

    /// Unknown or empty raw values fall back to ChatGPT style without crashing.
    static func resolved(_ raw: String?) -> InFlightShimmerStyle {
        guard let raw, !raw.isEmpty, let style = InFlightShimmerStyle(rawValue: raw) else {
            return .default
        }
        return style
    }

    var debugCommand: String { "shimmer-\(rawValue)" }

    static func fromDebugCommand(_ command: String) -> InFlightShimmerStyle? {
        guard command.hasPrefix("shimmer-") else { return nil }
        let raw = String(command.dropFirst("shimmer-".count))
        return InFlightShimmerStyle(rawValue: raw)
    }
}

/// Ported from mdo91/AI-Animation-Demo ShimmeringText, with every text preset.
/// TimelineView is forced unpaused and scenePhase active for the HUD panel.
struct InFlightPromptShimmer: View {
    var text: String
    var style: InFlightShimmerStyle = .default
    /// Nil keeps the style's demo weight at the prompt row size.
    var font: Font? = nil

    var body: some View {
        let preset = style.preset
        let resolvedFont = font ?? style.promptFont
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = Self.phase(
                at: context.date,
                duration: preset.duration,
                repeatDelay: preset.repeatDelay
            )
            Text(text)
                .font(resolvedFont)
                .foregroundStyle(preset.usesOverlay ? Color.secondary : .clear)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay {
                    GeometryReader { geometry in
                        shimmerBand(in: geometry, phase: phase, preset: preset)
                    }
                    .mask(
                        Text(text)
                            .font(resolvedFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    )
                    .blendMode(preset.usesOverlay ? .plusLighter : .normal)
                }
        }
        .environment(\.scenePhase, .active)
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private func shimmerBand(
        in geometry: GeometryProxy,
        phase: CGFloat,
        preset: ShimmerPreset
    ) -> some View {
        let width = geometry.size.width
        if preset.usesOverlay {
            let bandWidth = max(width * 0.6, 24)
            LinearGradient(
                colors: preset.gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bandWidth, height: geometry.size.height, alignment: .leading)
            .offset(x: -bandWidth + phase * (width + bandWidth))
        } else {
            LinearGradient(
                colors: preset.gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 3, height: geometry.size.height, alignment: .leading)
            .offset(x: -width * 2 + phase * width * 2)
        }
    }

    /// 0...1 during the sweep, then 0 while resting for `repeatDelay`.
    static func phase(at date: Date, duration: TimeInterval, repeatDelay: TimeInterval) -> CGFloat {
        let cycleLength = duration + repeatDelay
        guard cycleLength > 0 else { return 0 }
        let cyclePosition = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleLength)
        guard cyclePosition < duration else { return 0 }
        return CGFloat(cyclePosition / duration)
    }
}

private struct ShimmerPreset: Sendable {
    var gradientColors: [Color]
    var duration: TimeInterval
    var repeatDelay: TimeInterval
    var usesOverlay: Bool
}

private extension InFlightShimmerStyle {
    /// Demo fonts scaled to the prompt row so the field height stays stable.
    var promptFont: Font {
        switch self {
        case .chatGPTStyle:
            .system(size: PromptLayout.fontSize).weight(.medium)
        case .grokStyle:
            .system(size: PromptLayout.fontSize, design: .rounded).weight(.semibold)
        case .shimmeringText:
            .system(size: PromptLayout.fontSize, design: .rounded).weight(.bold)
        case .summerizingTheText:
            .system(size: PromptLayout.fontSize).weight(.regular)
        case .processingLabel:
            .system(size: PromptLayout.fontSize).weight(.medium)
        }
    }

    var preset: ShimmerPreset {
        switch self {
        case .chatGPTStyle:
            let gray = Color.secondary
            return ShimmerPreset(
                gradientColors: [gray, gray.opacity(0.45), gray, gray.opacity(0.45), gray],
                duration: 2.0,
                repeatDelay: 0,
                usesOverlay: false
            )
        case .grokStyle:
            return ShimmerPreset(
                gradientColors: [.blue, .purple, .pink, .blue],
                duration: 2.0,
                repeatDelay: 0,
                usesOverlay: false
            )
        case .shimmeringText:
            return ShimmerPreset(
                gradientColors: [.blue, .purple, .pink, .blue],
                duration: 2.0,
                repeatDelay: 0,
                usesOverlay: false
            )
        case .summerizingTheText:
            return ShimmerPreset(
                gradientColors: [.clear, Color.white.opacity(0.1), .clear],
                duration: 2.0,
                repeatDelay: 0.5,
                usesOverlay: true
            )
        case .processingLabel:
            return ShimmerPreset(
                gradientColors: [.clear, Color.white.opacity(0.1), .clear],
                duration: 1.5,
                repeatDelay: 0,
                usesOverlay: true
            )
        }
    }
}

/// Ported from mdo91/AI-Animation-Demo PulsingOrb. Driven by TimelineView so it
/// keeps moving inside the nonactivating HUD panel.
struct PulsingOrbIndicator: View {
    var diameter: CGFloat = HUDMetrics.controlSize

    private let gradientColors: [Color] = [.blue, .purple, .pink]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let pulse = Self.ringProgress(t: t, index: index)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.2, diameter * 0.08)
                        )
                        .scaleEffect(0.75 + pulse * 0.85)
                        .opacity(0.7 * (1 - pulse))
                }

                let core = Self.coreScale(t: t)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, Color.blue.opacity(0.9), .purple],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 1,
                            endRadius: diameter * 0.7
                        )
                    )
                    .scaleEffect(core)
                    .shadow(color: .purple.opacity(0.45), radius: diameter * 0.25)
                    .shadow(color: .blue.opacity(0.35), radius: diameter * 0.12)
            }
            .frame(width: diameter, height: diameter)
        }
        .environment(\.scenePhase, .active)
        .accessibilityLabel("Pulsing orb")
    }

    static func ringProgress(t: Double, index: Int) -> CGFloat {
        let period = 2.4
        let delay = Double(index) * 0.8
        let local = (t - delay).truncatingRemainder(dividingBy: period)
        let u = max(0, local) / period
        return CGFloat(1 - pow(1 - u, 2))
    }

    static func coreScale(t: Double) -> CGFloat {
        let period = 1.6
        let u = t.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 - 0.5 * cos(u * .pi * 2)
        return 0.94 + 0.12 * CGFloat(wave)
    }
}
