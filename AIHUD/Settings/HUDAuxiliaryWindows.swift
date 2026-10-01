import AppKit
import SwiftUI

extension HUDController {
    func openSettings() {
        present(window: settingsWindow ?? makeSettingsWindow(), remembering: { settingsWindow = $0 })
    }

    func openDebug() {
        DebugSettings.saveEnabled(true, to: .standard)
        DebugPreviewStore.shared.setDebugEnabled(true)
        DebugHTTPTranscript.setArmed(true)
        model.debugDriven = true
        stopCapture()
        show()
        let window = debugWindow ?? makeDebugWindow()
        debugWindow = window
        placeDebugWindow(window)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func openTranscript() {
        DebugSettings.saveEnabled(true, to: .standard)
        DebugPreviewStore.shared.setDebugEnabled(true)
        DebugHTTPTranscript.setArmed(true)
        let window = transcriptWindow ?? makeTranscriptWindow()
        transcriptWindow = window
        DebugTranscriptStore.shared.windowVisible = true
        if let screen = NSScreen.screens.first(where: { screen in
            if let frame = statusItemFrame, screen.frame.intersects(frame) { return true }
            return false
        }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 24,
                y: visible.midY - size.height / 2
            ))
        }
        // Transcript is a normal titled window so scrolling and copy work.
        // Do not activate just to keep the HUD; activate only for this reader.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func present(window: NSWindow, remembering: (NSWindow) -> Void) {
        remembering(window)
        if let screen = NSScreen.screens.first(where: { screen in
            if let frame = statusItemFrame, screen.frame.intersects(frame) { return true }
            return false
        }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func placeDebugWindow(_ window: NSWindow) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var origin = NSPoint(
            x: panel.frame.maxX + 24,
            y: panel.frame.maxY - window.frame.height
        )
        if origin.x + window.frame.width > visible.maxX - 16 {
            origin.x = panel.frame.minX - window.frame.width - 24
        }
        origin.x = min(max(origin.x, visible.minX + 16), visible.maxX - window.frame.width - 16)
        origin.y = min(max(origin.y, visible.minY + 16), visible.maxY - window.frame.height - 16)
        window.setFrameOrigin(origin)
    }

    func makeSettingsWindow() -> NSWindow {
        let host = NSHostingView(rootView: SettingsView(store: store, model: model))
        host.safeAreaRegions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: HUDMetrics.settingsSize.width, height: HUDMetrics.settingsSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.contentView = host
        window.contentMinSize = NSSize(width: 680, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func makeDebugWindow() -> NSWindow {
        let host = NSHostingView(rootView: DebugView(model: model, onCommand: { [weak self] command in
            self?.applyDebugCommand(command)
        }))
        host.safeAreaRegions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: HUDMetrics.debugSize.width, height: HUDMetrics.debugSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Debug")
        window.contentView = host
        window.contentMinSize = HUDMetrics.debugSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func makeTranscriptWindow() -> NSWindow {
        let host = NSHostingView(rootView: DebugTranscriptView())
        host.safeAreaRegions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Axiom transcript")
        window.contentView = host
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let closingSettings = window == settingsWindow
        let closingDebug = window == debugWindow
        let closingTranscript = window == transcriptWindow
        if closingTranscript {
            DebugTranscriptStore.shared.windowVisible = false
        }
        guard closingSettings || closingDebug || closingTranscript else { return }
        let settingsOpen = !closingSettings && settingsWindow?.isVisible == true
        let debugOpen = !closingDebug && debugWindow?.isVisible == true
        let transcriptOpen = !closingTranscript && transcriptWindow?.isVisible == true
        if closingDebug {
            model.debugDriven = false
            startVoiceIfNeeded()
        }
        if !settingsOpen && !debugOpen && !transcriptOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
