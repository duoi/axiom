import AppKit
import Observation
import SwiftUI

/// Decision helpers for the Apple Intelligence-style glow borders.
enum IntelligenceGlowPolicy {
    /// Modest continuous corner when the captured window radius is unknown.
    static let windowCornerRadius: CGFloat = 14
    static var hudCornerRadius: CGFloat { HUDMetrics.cornerRadius }

    /// Whole-card glow only while dictation is actively writing into the field.
    static func showsDictationBorder(dictating: Bool) -> Bool {
        dictating
    }

    static func cornerRadius(isHUD: Bool) -> CGFloat {
        isHUD ? hudCornerRadius : windowCornerRadius
    }

    static func context(dictating: Bool) -> IntelligenceGlowContext {
        dictating ? .listening : .capture
    }
}

enum IntelligenceGlowContext: String, CaseIterable, Identifiable, Sendable {
    case listening
    case capture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: "Listening"
        case .capture: "Capture"
        }
    }
}

/// Matches Livsy90/IntelligenceGlow README preview names.
enum IntelligenceGlowVariation: String, CaseIterable, Identifiable, Sendable {
    case overlay
    case sweep
    case background
    case glassBackground
    case sweepPlusGlow

    static let `default`: IntelligenceGlowVariation = .overlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overlay: "Intelligence Glow Overlay"
        case .sweep: "Intelligence Sweep"
        case .background: "Intelligence Glow Background"
        case .glassBackground: "Intelligence Glow Glass Background"
        case .sweepPlusGlow: "Intelligence Sweep + Intelligence Glow"
        }
    }

    var usesGlow: Bool {
        switch self {
        case .overlay, .background, .glassBackground, .sweepPlusGlow: true
        case .sweep: false
        }
    }

    var usesSweep: Bool {
        switch self {
        case .sweep, .sweepPlusGlow: true
        case .overlay, .background, .glassBackground: false
        }
    }
}

/// Tuned debug knobs for one glow context. Values are rendered as-is (no extra scale).
struct IntelligenceGlowPreset: Equatable, Sendable {
    var variation: IntelligenceGlowVariation
    var padding: CGFloat
    var lineWidthScale: CGFloat
    var blurScale: CGFloat
    var opacity: CGFloat
    var updateInterval: TimeInterval
    var animationSpeed: Double
    var blurRadius: CGFloat
    var sweepLineWidth: CGFloat
    var sweepSpan: Double
    var sweepOffset: Double

    /// Whole-card dictation / Listening.
    static let listening = IntelligenceGlowPreset(
        variation: .overlay,
        padding: 20,
        lineWidthScale: 0.3,
        blurScale: 1,
        opacity: 0.3,
        updateInterval: 0.4,
        animationSpeed: 1,
        blurRadius: 45,
        sweepLineWidth: 1.6,
        sweepSpan: 90,
        sweepOffset: 220
    )

    /// Window / screen capture highlight and flash-highlight.
    static let capture = IntelligenceGlowPreset(
        variation: .glassBackground,
        padding: 25.95,
        lineWidthScale: 0.5,
        blurScale: 2,
        opacity: 0.6,
        updateInterval: 0.4,
        animationSpeed: 1,
        blurRadius: 45,
        sweepLineWidth: 4,
        sweepSpan: 90,
        sweepOffset: 220
    )

    static func factory(_ context: IntelligenceGlowContext) -> IntelligenceGlowPreset {
        switch context {
        case .listening: .listening
        case .capture: .capture
        }
    }
}

/// Resolved stroke weights drawn by the overlay panel.
struct IntelligenceGlowSpec: Equatable, Sendable {
    var padding: CGFloat
    var lineWidths: [CGFloat]
    var blurs: [CGFloat]
    var opacity: CGFloat
    var updateInterval: TimeInterval
    var animationDurations: [TimeInterval]
    var blurRadius: CGFloat
    var sweepLineWidth: CGFloat
    var sweepSpan: Double
    var sweepOffset: Double
    var animationSpeed: Double

    static let baseLineWidths: [CGFloat] = [4, 7, 10, 14]
    static let baseBlurs: [CGFloat] = [0, 4, 10, 14]
    static let baseAnimationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0]

    static func resolved(from preset: IntelligenceGlowPreset) -> IntelligenceGlowSpec {
        IntelligenceGlowSpec(
            padding: preset.padding,
            lineWidths: baseLineWidths.map { $0 * preset.lineWidthScale },
            blurs: baseBlurs.map { $0 * preset.blurScale },
            opacity: preset.opacity,
            updateInterval: preset.updateInterval,
            animationDurations: baseAnimationDurations,
            blurRadius: preset.blurRadius,
            sweepLineWidth: preset.sweepLineWidth,
            sweepSpan: preset.sweepSpan,
            sweepOffset: preset.sweepOffset,
            animationSpeed: preset.animationSpeed
        )
    }
}

// Port of Livsy90/IntelligenceGlow for macOS. The upstream package declares
// iOS-only platforms, so we keep the same stroke technique here instead of
// adding a broken dependency.

extension Array where Element == Gradient.Stop {
    static var intelligenceStyle: [Gradient.Stop] {
        [Color]
            .intelligenceColors
            .map {
                Gradient.Stop(color: $0, location: Double.random(in: 0...1))
            }
            .sorted {
                $0.location < $1.location
            }
    }
}

extension Array where Element == Color {
    static var intelligenceColors: [Color] {
        [
            Color(red: 188 / 255, green: 130 / 255, blue: 243 / 255),
            Color(red: 245 / 255, green: 185 / 255, blue: 234 / 255),
            Color(red: 141 / 255, green: 159 / 255, blue: 255 / 255),
            Color(red: 255 / 255, green: 103 / 255, blue: 120 / 255),
            Color(red: 255 / 255, green: 186 / 255, blue: 113 / 255),
            Color(red: 198 / 255, green: 134 / 255, blue: 255 / 255)
        ]
    }
}

extension View {
    @MainActor
    func intelligenceBackground<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping @autoclosure () -> [Gradient.Stop] = .intelligenceStyle
    ) -> some View {
        background(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations,
                gradientGenerator: gradientGenerator
            )
        )
    }

    @MainActor
    func intelligenceOverlay<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping @autoclosure () -> [Gradient.Stop] = .intelligenceStyle
    ) -> some View {
        overlay(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations,
                gradientGenerator: gradientGenerator
            )
        )
    }

    @MainActor
    func intelligenceSweep<S: InsettableShape>(
        in shape: S,
        borderColor: Color = .primary,
        colors: [Color] = .intelligenceColors,
        blurRadius: CGFloat = 18,
        lineWidth: CGFloat = 0.7,
        sweepSpan: Double = 130,
        sweepOffset: Double = 140
    ) -> some View {
        modifier(
            IntelligenceSweepModifier(
                shape: shape,
                borderColor: borderColor,
                colors: colors,
                blurRadius: blurRadius,
                lineWidth: lineWidth,
                sweepSpan: sweepSpan,
                sweepOffset: sweepOffset
            )
        )
    }
}

extension InsettableShape {
    @MainActor
    func intelligenceStroke(
        lineWidths: [CGFloat] = [6, 9, 11, 15],
        blurs: [CGFloat] = [0, 4, 12, 15],
        updateInterval: TimeInterval = 0.4,
        animationDurations: [TimeInterval] = [0.5, 0.6, 0.8, 1.0],
        gradientGenerator: @MainActor @Sendable @escaping () -> [Gradient.Stop] = { .intelligenceStyle }
    ) -> some View {
        IntelligenceStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations,
            gradientGenerator: gradientGenerator
        )
        .allowsHitTesting(false)
    }
}

private struct IntelligenceStrokeView<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]
    let gradientGenerator: @MainActor @Sendable () -> [Gradient.Stop]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = .intelligenceStyle

    var body: some View {
        let layerCount = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center
        )

        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[i])
                    .blur(radius: blurs[i])
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .easeInOut(duration: animationDurations[i]),
                        value: stops.map(\.location)
                    )
            }
        }
        .task(id: updateInterval) {
            while !Task.isCancelled {
                stops = gradientGenerator()
                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}

private struct IntelligenceSweepModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let borderColor: Color
    let colors: [Color]
    let blurRadius: CGFloat
    let lineWidth: CGFloat
    let sweepSpan: Double
    let sweepOffset: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.stroke(borderColor.opacity(0.35), lineWidth: lineWidth)
                    if reduceMotion {
                        sweepContent(rotation: 0)
                    } else {
                        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                            let rotation = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 2.6) / 2.6 * 360
                            sweepContent(rotation: rotation)
                        }
                    }
                }
                .padding(0.5)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private func sweepContent(rotation: Double) -> some View {
        let borderGradient = AngularGradient(
            colors: [.clear, borderColor, .clear],
            center: .center,
            startAngle: .degrees(sweepOffset + rotation),
            endAngle: .degrees(sweepOffset + sweepSpan + rotation)
        )
        let sweepGradient = LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        ZStack {
            shape
                .fill(sweepGradient)
                .mask {
                    Rectangle()
                        .overlay {
                            shape
                                .blur(radius: blurRadius)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .mask {
                    shape
                        .fill(borderGradient)
                        .blur(radius: blurRadius / 1.5)
                        .padding(-blurRadius * 2)
                }

            shape.stroke(borderGradient, lineWidth: lineWidth)
        }
    }
}
