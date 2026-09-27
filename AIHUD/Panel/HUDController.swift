import AppKit
import SwiftUI

@MainActor
final class HUDController: NSObject, NSWindowDelegate {
    let panel = HUDPanel()
    let model: HUDModel
    let store: EndpointStore

    private var hosting: ClickThroughHosting<HUDView>?
    private var glass: NSGlassEffectView?
    private var solid: SolidCardView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var menuBegin: NSObjectProtocol?
    private var menuEnd: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var reduceTransparency = false

    init(store: EndpointStore) {
        self.store = store
        self.model = HUDModel(store: store)
        super.init()
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onAddContext = { [weak self] in self?.addContext() }
        model.onLayout = { [weak self] in self?.syncFrame() }
        panel.onCancel = { [weak self] in self?.userDismiss(clickOutside: false) }
        panel.delegate = self
        installChrome()
        installMonitors()
    }

    func toggle() {
        if panel.isVisible {
            userDismiss(clickOutside: false)
        } else {
            show()
        }
    }

    func show() {
        if panel.isVisible {
            panel.orderFrontRegardless()
            panel.makeKey()
            DispatchQueue.main.async { [weak self] in
                self?.model.focusField()
            }
            return
        }
        rebuildChromeIfNeeded()
        let height = measuredHeight()
        panel.centerOnMouseScreen(height: height)
        syncFrame(animated: false)
        panel.reveal()
        DispatchQueue.main.async { [weak self] in
            self?.model.focusField()
        }
    }

    func shutdown() {
        model.cancelForQuit()
    }

    private func userDismiss(clickOutside: Bool) {
        guard model.dismiss(clickOutside: clickOutside) else { return }
        guard panel.isVisible else { return }
        panel.fadeOut { }
    }

    private func installChrome() {
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let host = ClickThroughHosting(rootView: HUDView(model: model, store: store))
        host.safeAreaRegions = []
        host.setContentHuggingPriority(.required, for: .vertical)
        hosting = host
        mount(host)
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildChromeIfNeeded(force: true)
            }
        }
    }

    private func rebuildChromeIfNeeded(force: Bool = false) {
        let next = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if !force && next == reduceTransparency && panel.contentView != nil { return }
        reduceTransparency = next
        guard let hosting else { return }
        mount(hosting)
        syncFrame(animated: false)
    }

    private func mount(_ hosting: NSView) {
        hosting.removeFromSuperview()
        if reduceTransparency {
            let card = solid ?? SolidCardView(frame: NSRect(x: 0, y: 0, width: 560, height: 110))
            solid = card
            card.embed(hosting)
            glass?.contentView = nil
            panel.contentView = card
        } else {
            let glassView = glass ?? NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 560, height: 110))
            glass = glassView
            glassView.style = .clear
            glassView.cornerRadius = 24
            glassView.tintColor = nil
            if #available(macOS 27.0, *) {
                glassView.effectIsInteractive = true
            }
            glassView.contentView = hosting
            panel.contentView = glassView
        }
        clipHosting(hosting)
    }

    private func clipHosting(_ hosting: NSView) {
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = 24
        hosting.layer?.masksToBounds = true
    }

    private func measuredHeight() -> CGFloat {
        guard let hosting else { return 110 }
        hosting.layoutSubtreeIfNeeded()
        return max(100, hosting.fittingSize.height)
    }

    private func syncFrame(animated: Bool = true) {
        let height = measuredHeight()
        panel.resizePinnedTop(to: height, animated: animated && panel.isVisible)
        hosting?.frame = NSRect(origin: .zero, size: NSSize(width: 560, height: panel.frame.height))
        panel.contentView?.frame = NSRect(origin: .zero, size: panel.frame.size)
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.clickOutside(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.clickOutside(event)
            }
            return event
        }
        menuBegin = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.menuTracking = true }
        }
        menuEnd = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.menuTracking = false }
        }
    }

    private func clickOutside(_ event: NSEvent) {
        guard panel.isVisible else { return }
        if panel.menuTracking || menuWindowIsOpen || panel.attachedSheet != nil { return }
        if settingsWindow?.isVisible == true { return }
        if let window = event.window {
            if window === panel || window === settingsWindow { return }
            let name = String(describing: type(of: window))
            if name.contains("Menu") { return }
        }
        let point = screenPoint(of: event)
        if panel.frame.contains(point) { return }
        if let statusFrame = statusItemFrame, statusFrame.contains(point) { return }
        if let settings = settingsWindow, settings.isVisible, settings.frame.contains(point) { return }
        userDismiss(clickOutside: true)
    }

    private func screenPoint(of event: NSEvent) -> NSPoint {
        guard let window = event.window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    var statusItemFrame: NSRect?

    private var menuWindowIsOpen: Bool {
        NSApp.windows.contains { window in
            guard window.isVisible, window !== panel else { return false }
            let name = String(describing: type(of: window))
            return name.contains("Menu")
        }
    }

    private func addContext() {
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.allowedContentTypes = [
            .plainText, .utf8PlainText, .text, .json, .png, .jpeg, .gif, .webP, .heic
        ]
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK else {
                self?.model.focusField()
                return
            }
            for url in picker.urls {
                self.ingest(url)
            }
            self.model.focusField()
        }
    }

    private func ingest(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            model.reportAttachmentError(.unreadableImage)
            return
        }
        switch AttachmentPolicy.prepare(data: data, filename: url.lastPathComponent, existingCount: model.session.chips.count) {
        case .success(let chip):
            model.addChip(chip)
        case .failure(let error):
            model.reportAttachmentError(error)
        }
    }

    func openSettings() {
        if panel.isVisible {
            _ = model.dismiss(clickOutside: false)
            panel.orderOut(nil)
        }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingView(rootView: SettingsView(store: store, onSave: { [weak self] in
            self?.settingsWindow?.close()
        }))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI HUD Settings"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == settingsWindow else { return }
        NSApp.deactivate()
    }
}

final class ClickThroughHosting<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SolidCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { return nil }

    func embed(_ child: NSView) {
        if child.superview !== self {
            addSubview(child)
        }
        child.frame = bounds
        child.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }
}
