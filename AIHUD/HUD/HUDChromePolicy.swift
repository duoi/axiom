import AppKit
import Foundation

/// When the Composing orb replaces the send icon.
enum ReplyWaitingChrome {
    static func showsComposingOrb(phase: Phase, answer: String) -> Bool {
        answer.isEmpty && (phase == .waiting || phase == .streaming)
    }
}

/// Reply band and expand chevron. Waiting with no text stays compact.
enum HistoryChromePolicy {
    static func showsReplyRegion(
        answer: String,
        phase: Phase,
        historyExpanded: Bool,
        toolLine: String? = nil
    ) -> Bool {
        if historyExpanded { return true }
        if let toolLine, !toolLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if case .failed = phase { return true }
        return false
    }

    static func showsExpandChevron(
        answer: String,
        phase: Phase,
        historyExpanded: Bool,
        hasUserTurns: Bool,
        toolLine: String? = nil
    ) -> Bool {
        guard hasUserTurns else { return false }
        return showsReplyRegion(
            answer: answer,
            phase: phase,
            historyExpanded: historyExpanded,
            toolLine: toolLine
        )
    }
}

/// Prompt capsule plus separate pills. Flag-off still uses the 108pt plate.
enum HUDSplitChromeLayout {
    /// Wallpaper between the capsule and the pills.
    static let pillGap: CGFloat = 16
    /// Wallpaper between neighboring pills.
    static let pillSpacing: CGFloat = 8
    /// Window room outside the card. The open spring swings the edge pills about 5pt out.
    static let windowMargin = NSEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
    /// Idle window stays `rowHeight + pillGap + pillHeight`, which is `minCardHeight`.
    static let pillHeight: CGFloat = HUDMetrics.minCardHeight - HUDMetrics.rowHeight - pillGap

    struct Frames: Equatable, Sendable {
        var placement: HUDLayout.LipPlacement
        var pills: [CGRect]
    }

    static func panelHeight(splitEnabled: Bool, settledCapsuleHeight: CGFloat, hasLip: Bool) -> CGFloat {
        if !splitEnabled {
            return HUDLayout.windowHeight(card: settledCapsuleHeight, hasLip: hasLip)
        }
        return settledCapsuleHeight + pillGap + pillHeight + (hasLip ? HUDLayout.lipVisible : 0)
    }

    /// Idle one-row stays a pill. The corner eases to 24pt across one prompt line.
    static func capsuleCornerRadius(height: CGFloat) -> CGFloat {
        let row = HUDMetrics.rowHeight
        if height <= row + 0.5 {
            return height / 2
        }
        let span = max(PromptLayout.promptLineHeight, 1)
        let unit = min(1, (height - row) / span)
        let eased = CGFloat(HUDFrameMotion.easeInOut(Double(unit)))
        let pill = row / 2
        return pill + (HUDMetrics.cornerRadius - pill) * eased
    }

    static func frames(
        splitEnabled: Bool,
        settledCapsuleHeight: CGFloat,
        panelHeight: CGFloat,
        showLip: Bool,
        cardWidth: CGFloat,
        leadingWidths: [CGFloat],
        trailingWidths: [CGFloat]
    ) -> Frames {
        if !splitEnabled {
            return Frames(
                placement: HUDLayout.lipPlacement(
                    windowHeight: panelHeight,
                    cardHeight: settledCapsuleHeight,
                    cardWidth: cardWidth,
                    hasLip: showLip
                ),
                pills: []
            )
        }
        let capsule = max(0, settledCapsuleHeight)
        let idle = capsule + pillGap + pillHeight
        let revealed = showLip ? min(HUDLayout.lipVisible, max(0, panelHeight - idle)) : 0
        let lipWindow = capsule + revealed
        let inner = HUDLayout.lipPlacement(
            windowHeight: lipWindow,
            cardHeight: capsule,
            cardWidth: cardWidth,
            hasLip: showLip && revealed > 0,
            minimumCardHeight: capsule
        )
        let dy = panelHeight - lipWindow
        let placement = HUDLayout.LipPlacement(
            plate: inner.plate.offsetBy(dx: 0, dy: dy),
            lip: inner.lip.offsetBy(dx: 0, dy: dy),
            revealed: inner.revealed
        )
        let rowMaxY = placement.plate.minY - placement.revealed - pillGap
        let pills = pillFrames(
            leadingWidths: leadingWidths,
            trailingWidths: trailingWidths,
            rowMaxY: rowMaxY,
            cardWidth: cardWidth
        )
        return Frames(placement: placement, pills: pills)
    }

    static let chipBand: CGFloat = HUDMetrics.rowHeight / 2

    static func promptBlock(extraLines: Int) -> CGFloat {
        let extra = max(0, extraLines)
        let line = PromptLayout.promptLineHeight
        return HUDMetrics.rowHeight + CGFloat(extra) * line
    }

    static func chipOpacity(displayedCapsule: CGFloat, promptBlock: CGFloat) -> CGFloat {
        let span = max(chipBand, 1)
        return min(1, max(0, (displayedCapsule - promptBlock) / span))
    }

    static func lipCopyOpacity(revealed: CGFloat) -> CGFloat {
        min(1, max(0, revealed / HUDLayout.lipVisible))
    }

    static func pointHitsChrome(_ point: CGPoint, frames: Frames, splitEnabled: Bool) -> Bool {
        if frames.placement.plate.contains(point) { return true }
        if frames.placement.revealed > 0.5 {
            let lip = CGRect(
                x: frames.placement.lip.minX,
                y: frames.placement.plate.minY - frames.placement.revealed,
                width: frames.placement.lip.width,
                height: frames.placement.revealed
            )
            if lip.contains(point) { return true }
        }
        if !splitEnabled { return false }
        return frames.pills.contains { $0.contains(point) }
    }

    private static func pillFrames(
        leadingWidths: [CGFloat],
        trailingWidths: [CGFloat],
        rowMaxY: CGFloat,
        cardWidth: CGFloat
    ) -> [CGRect] {
        let y = rowMaxY - pillHeight
        var pills: [CGRect] = []
        var x: CGFloat = 0
        for width in leadingWidths {
            pills.append(CGRect(x: x, y: y, width: width, height: pillHeight))
            x += width + pillSpacing
        }
        var trailing: [CGRect] = []
        var right = cardWidth
        for width in trailingWidths.reversed() {
            right -= width
            trailing.append(CGRect(x: right, y: y, width: width, height: pillHeight))
            right -= pillSpacing
        }
        pills.append(contentsOf: trailing.reversed())
        return pills
    }
}

enum HUDPillID: Equatable, Sendable {
    case preset
    case capture
    case context
    /// Add context as a paperclip circle, for rows with the Agent pill.
    case contextIcon
    case shortcut
    case mic
    case send

    var isCircle: Bool { self == .mic || self == .send || self == .contextIcon }

    static func columns(showsPreset: Bool) -> (leading: [HUDPillID], trailing: [HUDPillID]) {
        var leading: [HUDPillID] = []
        // The Agent pill leaves no room for the Add context label beside the shortcut.
        if showsPreset {
            leading.append(contentsOf: [.preset, .capture, .contextIcon])
        } else {
            leading.append(contentsOf: [.capture, .context])
        }
        return (leading, [.shortcut, .mic, .send])
    }
}

enum HUDChromeRegion: Equatable {
    case plate
    case capsule
    case pill(HUDPillID)
}

/// Prompt field while a turn is in flight: keep the submitted string, lock editing.
enum PromptInFlightPolicy {
    static func isInFlight(_ phase: Phase) -> Bool {
        phase == .waiting || phase == .streaming
    }

    static func isEditable(phase: Phase) -> Bool {
        !isInFlight(phase)
    }

    static func promptDraft(whileSending submitted: String) -> String {
        submitted
    }

    static func promptDraftAfterSuccess() -> String {
        ""
    }

    static func promptDraftAfterFailure(submitted: String) -> String {
        submitted
    }

}

enum AuxiliaryWindowLevel {
    /// Over the card only while Axiom is active and you are in that window, its sheet, or its popover.
    /// Otherwise it is a normal window, so other apps can cover it.
    static func level(appActive: Bool, isKey: Bool, ownsFocus: Bool, cardLevel: NSWindow.Level) -> NSWindow.Level {
        appActive && (isKey || ownsFocus) ? cardLevel : .normal
    }
}
