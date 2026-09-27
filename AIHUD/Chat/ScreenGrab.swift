import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenGrabError: Error, Equatable {
    case permission
    case failed
}

enum ScreenGrab {
    static func capture(
        excluding windowID: CGWindowID,
        displayID: CGDirectDisplayID?,
        frontPID: pid_t?,
        target: CaptureTarget
    ) async throws -> CGImage {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenGrabError.permission
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let filter: SCContentFilter
        switch target {
        case .screen:
            guard let display = display(in: content, matching: displayID) else {
                throw ScreenGrabError.failed
            }
            let excluded = content.windows.filter { $0.windowID == windowID }
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            configuration.width = display.width
            configuration.height = display.height
        case .window:
            guard let window = frontWindow(in: content, excluding: windowID, frontPID: frontPID) else {
                throw ScreenGrabError.failed
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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
