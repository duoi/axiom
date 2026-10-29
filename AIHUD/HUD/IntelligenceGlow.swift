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
}

enum IntelligenceGlowContext: String, CaseIterable, Identifiable, Sendable {
    case listening
    case capture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: String(localized: "Listening")
        case .capture: String(localized: "Capture")
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
        case .overlay: String(localized: "Intelligence Glow Overlay")
        case .sweep: String(localized: "Intelligence Sweep")
        case .background: String(localized: "Intelligence Glow Background")
        case .glassBackground: String(localized: "Intelligence Glow Glass Background")
        case .sweepPlusGlow: String(localized: "Intelligence Sweep + Intelligence Glow")
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
