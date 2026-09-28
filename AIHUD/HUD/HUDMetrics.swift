import AppKit
import CoreGraphics

struct HUDInsets: Equatable, Sendable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static func equal(_ value: CGFloat) -> HUDInsets {
        HUDInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

enum HUDMetrics {
    static let cardWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 24
    static let inset: CGFloat = 20
    static let pillInset: CGFloat = 8
    static var pillInsets: HUDInsets { .equal(pillInset) }
    static let rowHeight: CGFloat = 52
    static let controlSpacing: CGFloat = 20
    static let sidebarWidth: CGFloat = 184
    static let minCardHeight: CGFloat = 108
    static let settingsSize = CGSize(width: 900, height: 820)
    static let debugSize = CGSize(width: 440, height: 720)
}

enum HUDLayout {
    /// Visible peek below the plate. Extra window growth is this amount.
    static let lipVisible: CGFloat = 28
    /// The warning sits this far in from each side of the card, clear of the corner wings.
    static let lipInset: CGFloat = 24
    /// Bottom corners of the warning. Smaller than the plate so it reads as its own lip.
    static let lipCorner: CGFloat = 16
    static var lipHeight: CGFloat { lipVisible }
    /// Ignore sub-point and 1pt fittingSize flicker so the panel does not step.
    static let heightFlicker: CGFloat = 1

    static func cardHeight() -> CGFloat {
        HUDMetrics.minCardHeight
    }

    static func windowHeight(card: CGFloat, hasLip: Bool) -> CGFloat {
        max(HUDMetrics.minCardHeight, card) + (hasLip ? lipVisible : 0)
    }

    static func lipWidth(cardWidth: CGFloat) -> CGFloat {
        max(0, cardWidth - 2 * lipInset)
    }

    /// The warning only. It does not climb the plate corner.
    static func lipFrame(cardWidth: CGFloat) -> CGRect {
        CGRect(x: lipInset, y: 0, width: lipWidth(cardWidth: cardWidth), height: lipVisible)
    }

    /// Lets the warning show under the plate without clipping or reshaping the plate's continuous corner.
    static func applyLipWindowMask(to view: NSView, hasLip: Bool) {
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        guard hasLip, view.bounds.width > 1, view.bounds.height > 1 else {
            view.layer?.mask = nil
            return
        }
        view.layer?.cornerRadius = 0
        view.layer?.masksToBounds = false
        let mask = CALayer()
        mask.frame = view.bounds
        let cardHeight = max(HUDMetrics.minCardHeight, view.bounds.height - lipVisible)
        let plate = CALayer()
        plate.frame = CGRect(
            x: view.bounds.minX,
            y: view.bounds.minY + lipVisible,
            width: view.bounds.width,
            height: cardHeight
        )
        plate.backgroundColor = NSColor.white.cgColor
        plate.cornerRadius = HUDMetrics.cornerRadius
        plate.cornerCurve = .continuous
        plate.masksToBounds = true
        let band = CALayer()
        let lip = lipFrame(cardWidth: view.bounds.width)
        band.frame = lip.offsetBy(dx: view.bounds.minX, dy: view.bounds.minY)
        band.backgroundColor = NSColor.white.cgColor
        band.cornerRadius = lipCorner
        band.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        band.masksToBounds = true
        mask.addSublayer(plate)
        mask.addSublayer(band)
        view.layer?.mask = mask
    }

    static func settledHeight(
        proposed: CGFloat,
        previous: CGFloat,
        lineCount: Int,
        multiline: Bool
    ) -> CGFloat {
        let next = max(HUDMetrics.minCardHeight, proposed)
        let prior = max(HUDMetrics.minCardHeight, previous)
        let delta = next - prior
        if abs(delta) <= heightFlicker {
            return prior
        }
        let line = PromptLayout.lineHeight(for: PromptLayout.font())
        if multiline {
            let extra = max(0, lineCount - 1)
            if extra == 0, abs(delta) < line {
                return prior
            }
            if abs(delta) + heightFlicker >= line {
                return next
            }
            return prior
        }
        if abs(delta) < line {
            return prior
        }
        return next
    }

    static func framePinnedTop(current: NSRect, height: CGFloat) -> NSRect {
        let nextHeight = max(HUDMetrics.minCardHeight, height)
        var next = current
        next.size.width = HUDMetrics.cardWidth
        let delta = nextHeight - current.height
        next.size.height = nextHeight
        next.origin.y -= delta
        return next
    }
}

enum HUDLipChrome {
    /// Reference fill, sampled ~RGB(22, 16, 18) on black.
    static let fillTop = NSColor(srgbRed: 22 / 255, green: 16 / 255, blue: 18 / 255, alpha: 1)
    static let fillBottom = NSColor(srgbRed: 42 / 255, green: 22 / 255, blue: 26 / 255, alpha: 1)
    /// Dusty rose from the reference glyphs, not `systemRed`.
    static let ink = NSColor(srgbRed: 0.84, green: 0.51, blue: 0.58, alpha: 1)
    static let dismiss = NSColor.white.withAlphaComponent(0.58)
}

enum HUDErrorLip {
    enum Action: Equatable, Sendable {
        case voice
        case screen
        case none
    }

    enum Source: Equatable, Sendable {
        case failed
        case blocking
        case screen
        case voice
    }

    struct Message: Equatable, Sendable {
        var text: String
        var action: Action
        var source: Source
    }

    struct State: Equatable, Sendable {
        var phase: Phase
        var errorMessage: String?
        var screenNotice: String?
        var voiceStatus: String?
        var dismissed: Bool
    }

    static let screenPermission = "Allow Screen Recording in System Settings"
    static let screenFailed = "The screen capture failed."

    static func message(
        phase: Phase,
        blockingMessage: String?,
        screenNotice: String?,
        voiceStatus: String?,
        dismissed: Bool
    ) -> Message? {
        if case .failed(let text) = phase, !text.isEmpty {
            return Message(text: text, action: .none, source: .failed)
        }
        if phase == .composing, let blocking = blockingMessage, !blocking.isEmpty, !dismissed {
            return Message(text: blocking, action: .none, source: .blocking)
        }
        if let notice = screenNotice, !notice.isEmpty {
            return Message(
                text: notice,
                action: notice == screenPermission ? .screen : .none,
                source: .screen
            )
        }
        if let voice = voiceStatus, !voice.isEmpty {
            return Message(
                text: voice,
                action: VoiceStatusCopy.systemSettingsURL(for: voice) == nil ? .none : .voice,
                source: .voice
            )
        }
        return nil
    }

    static func dismiss(_ state: inout State, blockingMessage: String?) {
        guard let shown = message(
            phase: state.phase,
            blockingMessage: blockingMessage,
            screenNotice: state.screenNotice,
            voiceStatus: state.voiceStatus,
            dismissed: state.dismissed
        ) else {
            return
        }
        state.dismissed = true
        switch shown.source {
        case .failed:
            state.phase = .composing
            state.errorMessage = nil
        case .screen:
            state.screenNotice = nil
        case .voice:
            state.voiceStatus = nil
        case .blocking:
            break
        }
    }

    static func reveal(_ state: inout State) {
        state.dismissed = false
    }
}
