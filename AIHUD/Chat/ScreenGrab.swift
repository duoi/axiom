import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenGrabError: Error, Equatable {
    case permission
    case accessibility
    case failed
}

struct ScreenCaptureResult {
    var image: CGImage
    /// Quartz screen-coordinate frame (top-left of the main display) of the captured display or window.
    var highlightFrame: CGRect?
}

enum ScreenGrab {
    // Capture only reads preflight. Never call `CGRequestScreenCaptureAccess` on send:
    // that re-prompts when TCC does not recognize an ad-hoc rebuild.

    /// Settings control: request once and open the Screen Recording pane when not granted.
    static func settingsDecision(preflightGranted: Bool) -> PrivacyPromptDecision {
        preflightGranted ? .none : .requestAndOpenSettings
    }

    /// Window capture needs Accessibility to identify the target reliably.
    static func requiresAccessibility(for target: CaptureTarget, trusted: Bool) -> Bool {
        target == .window && !trusted
    }

    /// Every window this process owns: the card, pills, lip, and glow overlays.
    /// Leaving them out of the shot means the card never has to hide.
    static func excludedWindowIDs(_ windows: [(id: CGWindowID, pid: pid_t?)], ownPID: pid_t) -> [CGWindowID] {
        windows.filter { $0.pid == ownPID }.map(\.id)
    }

    @discardableResult
    static func requestAccessFromSettings() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func capture(
        excluding windowID: CGWindowID,
        displayID: CGDirectDisplayID?,
        frontPID: pid_t?,
        target: CaptureTarget,
        accessibilityTrusted: Bool = AccessibilityPermission.isTrusted
    ) async throws -> ScreenCaptureResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenGrabError.permission
        }
        if requiresAccessibility(for: target, trusted: accessibilityTrusted) {
            throw ScreenGrabError.accessibility
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let filter: SCContentFilter
        let highlightFrame: CGRect?
        switch target {
        case .screen:
            guard let display = display(in: content, matching: displayID) else {
                throw ScreenGrabError.failed
            }
            let own = Set(excludedWindowIDs(
                content.windows.map { ($0.windowID, $0.owningApplication?.processID) },
                ownPID: getpid()
            ))
            let excluded = content.windows.filter { $0.windowID == windowID || own.contains($0.windowID) }
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            configuration.width = display.width
            configuration.height = display.height
            // CGDisplayBounds is Quartz global (top-left main display). Same space as SCWindow.frame.
            highlightFrame = CGDisplayBounds(display.displayID)
        case .window:
            guard let window = frontWindow(in: content, excluding: windowID, frontPID: frontPID) else {
                throw ScreenGrabError.failed
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
            // SCWindow.frame is Quartz screen coordinates (top-left of the main display).
            highlightFrame = window.frame
        }
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return ScreenCaptureResult(image: image, highlightFrame: highlightFrame)
    }

    private static func frontWindow(
        in content: SCShareableContent,
        excluding windowID: CGWindowID,
        frontPID: pid_t?
    ) -> SCWindow? {
        let windows = content.windows.filter { window in
            window.windowID != windowID
                && window.isOnScreen
                && window.frame.width > 80
                && window.frame.height > 80
        }
        let owned = windows.filter { $0.owningApplication?.processID == frontPID }
        let pool = owned.isEmpty ? windows : owned
        return pool.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private static func display(in content: SCShareableContent, matching displayID: CGDirectDisplayID?) -> SCDisplay? {
        if let displayID, let match = content.displays.first(where: { $0.displayID == displayID }) {
            return match
        }
        return content.displays.first
    }
}
