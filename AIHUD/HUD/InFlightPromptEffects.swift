import SwiftUI

/// Locked in-flight prompt treatment. One grayscale sweep. Unknown raw values
/// fall back to it.
enum InFlightShimmerStyle: String, CaseIterable, Identifiable, Sendable {
    case whiteSweep = "white-sweep"

    static let `default`: InFlightShimmerStyle = .whiteSweep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whiteSweep: String(localized: "White sweep")
        }
    }

    var summary: String {
        switch self {
        case .whiteSweep:
            String(localized: "Dim white letters with a brighter highlight moving through them.")
        }
    }

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

/// Dim white glyphs with a white linear-gradient highlight masked to the letters.
/// TimelineView stays unpaused and scenePhase is forced active because the
/// nonactivating HUD panel reports background and would otherwise freeze the clock.
struct InFlightPromptShimmer: View {
    var text: String
    var style: InFlightShimmerStyle = .default

    var body: some View {
        let _ = style
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = Self.bandPhase(at: context.date, duration: Self.bandDuration)
            glyph(text)
                .foregroundStyle(Color.white.opacity(0.38))
                .overlay {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let band = max(width * 0.42, 36)
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white,
                                Color.white.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band, height: geometry.size.height, alignment: .leading)
                        .offset(x: -band + phase * (width + band))
                    }
                    .mask { glyph(text) }
                }
        }
        .environment(\.scenePhase, .active)
        .accessibilityLabel(text)
    }

    private func glyph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: PromptLayout.fontSize))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    static let bandDuration: TimeInterval = 1.8

    /// 0...1 across `duration`, then the next sweep starts immediately.
    static func bandPhase(at date: Date, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        let raw = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        let wrapped = raw < 0 ? raw + duration : raw
        return CGFloat(wrapped / duration)
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
