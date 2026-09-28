import AppKit
import SwiftUI

@MainActor
final class HUDController: NSObject, NSWindowDelegate {
    let panel = HUDPanel()
    let model: HUDModel
    let store: EndpointStore

    private var hosting: ClickThroughHosting<HUDView>?
    private var glass: NSGlassEffectView?
    private var glassContainer: NSGlassEffectContainerView?
    private var solid: SolidCardView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var menuBegin: NSObjectProtocol?
    private var menuEnd: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var debugWindow: NSWindow?
    private var reduceTransparency = false
    private var capture: VoiceCapture?
    private var lastWake: Date?
    private var dictationBase = ""
    private var openedFromWake = false
    private var openedAt: Date?
    private var silentSince: Date?
    private var voicePoll: Task<Void, Never>?

    init(store: EndpointStore) {
        self.store = store
        self.model = HUDModel(store: store)
        super.init()
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onAddContext = { [weak self] in self?.addContext() }
        model.onCaptureScreen = { [weak self] in self?.captureForSend() }
        model.onLayout = { [weak self] in self?.syncFrame() }
        model.onToggleDictation = { [weak self] in self?.toggleDictation() }
        model.onSetWake = { [weak self] on in self?.setWake(on) }
        model.onSendBegan = { [weak self] in self?.handleSendBegan() }
        store.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        panel.onCancel = { [weak self] in self?.userDismiss(clickOutside: false) }
        panel.delegate = self
        installChrome()
        installMonitors()
        startVoicePolling()
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
        model.cardIsKey = true
        DispatchQueue.main.async { [weak self] in
            self?.model.focusField()
        }
    }

    func shutdown() {
        voicePoll?.cancel()
        voicePoll = nil
        capture?.stop()
        capture = nil
        model.cancelForQuit()
    }

    func startVoiceIfNeeded() {
        guard store.wakeOnAxiom, !model.debugDriven else { return }
        Task { await startWakeCapture(prompt: false) }
    }

    private func userDismiss(clickOutside: Bool) {
        guard model.dismiss(clickOutside: clickOutside) else { return }
        endDictation(keepWakeCapture: true)
        guard panel.isVisible else { return }
        panel.fadeOut { }
    }

    private func installChrome() {
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        model.reduceTransparency = reduceTransparency
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
        model.reduceTransparency = next
        applyAppearance()
    }

    private func applyAppearance() {
        guard let hosting else { return }
        let wantSolid = HUDMaterial.usesSolidCard(reduceTransparency: reduceTransparency)
        let showingSolid = panel.contentView === solid
        if panel.contentView == nil || wantSolid != showingSolid {
            mount(hosting)
            syncFrame(animated: false)
            return
        }
        if !wantSolid {
            applyGlass(glass ?? CardGlassView())
        }
    }

    private func applyGlass(_ glassView: NSGlassEffectView) {
        let style = HUDMaterial.effectStyle(matte: store.usesMatte)
        glassView.style = style == .regular ? .regular : .clear
        glassView.cornerRadius = HUDMetrics.cornerRadius
        let veil = HUDMaterial.veilOpacity(glassAmount: store.glassAmount)
        glassView.tintColor = veil == 0 ? nil : NSColor.windowBackgroundColor.withAlphaComponent(veil)
        if #available(macOS 27.0, *) {
            glassView.effectIsInteractive = false
        }
        // Regular glass is opaque, so the window shadow becomes a black box while the panel is key.
        panel.hasShadow = style != .regular
        panel.invalidateShadow()
        (glassView as? CardGlassView)?.containKeyFringe()
    }

    private func mount(_ hosting: NSView) {
        hosting.removeFromSuperview()
        if HUDMaterial.usesSolidCard(reduceTransparency: reduceTransparency) {
            let card = solid ?? SolidCardView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight))
            solid = card
            card.embed(hosting)
            glass?.contentView = nil
            glassContainer?.contentView = nil
            panel.contentView = card
        } else {
            let glassView = glass ?? CardGlassView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight))
            glass = glassView
            applyGlass(glassView)
            glassView.contentView = hosting
            let container = glassContainer ?? NSGlassEffectContainerView(
                frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
            )
            glassContainer = container
            container.spacing = HUDMaterial.glassContainerSpacing
            let wrapper = container.contentView ?? NSView(frame: container.bounds)
            wrapper.wantsLayer = true
            wrapper.layer?.isOpaque = false
            wrapper.layer?.backgroundColor = NSColor.clear.cgColor
            wrapper.autoresizingMask = [.width, .height]
            if glassView.superview !== wrapper {
                glassView.removeFromSuperview()
                wrapper.addSubview(glassView)
            }
            glassView.frame = wrapper.bounds
            glassView.autoresizingMask = [.width, .height]
            container.contentView = wrapper
            panel.contentView = container
        }
        clipHosting(hosting)
    }

    private func clipHosting(_ hosting: NSView) {
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = HUDMetrics.cornerRadius
        hosting.layer?.masksToBounds = true
    }

    private func measuredHeight() -> CGFloat {
        guard let hosting else { return 110 }
        hosting.layoutSubtreeIfNeeded()
        return max(HUDMetrics.minCardHeight, hosting.fittingSize.height)
    }

    private func syncFrame(animated: Bool = true) {
        let height = measuredHeight()
        panel.resizePinnedTop(to: height, animated: animated && panel.isVisible)
        let bounds = NSRect(origin: .zero, size: NSSize(width: HUDMetrics.cardWidth, height: panel.frame.height))
        hosting?.frame = bounds
        glass?.frame = bounds
        glassContainer?.frame = bounds
        glassContainer?.contentView?.frame = bounds
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
        if model.voicePermissionPrompt { return }
        if store.keepHovering { return }
        if panel.menuTracking || menuWindowIsOpen || panel.attachedSheet != nil { return }
        if settingsWindow?.isVisible == true { return }
        if let window = event.window {
            if window === panel || window === settingsWindow || window === debugWindow { return }
            let name = String(describing: type(of: window))
            if name.contains("Menu") { return }
        }
        let point = screenPoint(of: event)
        if panel.frame.contains(point) { return }
        if let statusFrame = statusItemFrame, statusFrame.contains(point) { return }
        if let settings = settingsWindow, settings.isVisible, settings.frame.contains(point) { return }
        if let debug = debugWindow, debug.isVisible, debug.frame.contains(point) { return }
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

    private func captureForSend() {
        let displayID = panel.screen.flatMap { screen -> CGDirectDisplayID? in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }
        let windowID = CGWindowID(panel.windowNumber)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let target = store.captureTarget
        panel.orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            do {
                let image = try await ScreenGrab.capture(
                    excluding: windowID,
                    displayID: displayID,
                    frontPID: frontPID,
                    target: target
                )
                let jpeg = ScreenImage.jpeg(from: image)
                restorePanel()
                guard !jpeg.isEmpty else {
                    model.reportScreenFailure(permission: false)
                    return
                }
                model.beginSend(jpeg: jpeg, name: target.title)
            } catch let error as ScreenGrabError {
                restorePanel()
                model.reportScreenFailure(permission: error == .permission)
            } catch {
                restorePanel()
                model.reportScreenFailure(permission: false)
            }
        }
    }

    private func restorePanel() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            self?.model.focusField()
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
        present(window: settingsWindow ?? makeSettingsWindow(), remembering: { settingsWindow = $0 })
    }

    func openDebug() {
        DebugSettings.saveEnabled(true, to: .standard)
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

    func applyDebugCommand(_ command: String) {
        let next = DebugRouting.apply(command, to: model.debugSnapshot())
        model.apply(next)
        if !panel.isVisible {
            show()
        }
        if next.wantsCardKey == true {
            panel.makeKey()
            DispatchQueue.main.async { [weak self] in
                self?.model.focusField()
            }
        } else if next.wantsCardKey == false {
            debugWindow?.makeKey()
        }
    }

    private func present(window: NSWindow, remembering: (NSWindow) -> Void) {
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

    private func placeDebugWindow(_ window: NSWindow) {
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

    private func makeSettingsWindow() -> NSWindow {
        let host = NSHostingView(rootView: SettingsView(store: store, model: model))
        host.safeAreaRegions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: HUDMetrics.settingsSize.width, height: HUDMetrics.settingsSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = host
        window.contentMinSize = NSSize(width: 680, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func makeDebugWindow() -> NSWindow {
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
        window.title = "Debug"
        window.contentView = host
        window.contentMinSize = HUDMetrics.debugSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func setWake(_ on: Bool) {
        if on {
            Task { await startWakeCapture(prompt: true) }
            return
        }
        store.wakeOnAxiom = false
        if !model.dictating {
            stopCapture()
        }
    }

    private func toggleDictation() {
        if store.wakeOnAxiom {
            if let denied = VoicePermission.deniedSentence() {
                model.voiceStatus = denied
                return
            }
            if capture == nil {
                Task { await startWakeCapture(prompt: false) }
            }
            if model.dictating {
                setDictating(false)
            } else {
                dictationBase = model.session.draft
                setDictating(true)
            }
            return
        }
        if model.dictating {
            setDictating(false)
            stopCapture()
            return
        }
        if let denied = VoicePermission.deniedSentence() {
            model.voiceStatus = denied
            return
        }
        Task { await startDictationCapture() }
    }

    private func startWakeCapture(prompt: Bool) async {
        if model.debugDriven { return }
        if prompt {
            let allowed = await requestVoicePermission()
            if model.debugDriven { return }
            if !allowed {
                store.wakeOnAxiom = false
                model.voiceStatus = VoicePermission.deniedSentence() ?? VoiceStatusCopy.micDenied
                return
            }
            let asset = await VoiceCapture.ensureInstalled()
            if model.debugDriven { return }
            guard asset == .installed else {
                store.wakeOnAxiom = false
                model.voiceStatus = asset.statusSentence
                return
            }
            store.wakeOnAxiom = true
            model.voiceStatus = nil
            beginCapture()
            return
        }
        if VoicePermission.deniedSentence() != nil {
            return
        }
        let asset = await VoiceCapture.ensureInstalled()
        if model.debugDriven { return }
        guard asset == .installed else {
            return
        }
        beginCapture()
    }

    private func startDictationCapture() async {
        if model.debugDriven { return }
        if let denied = VoicePermission.deniedSentence() {
            model.voiceStatus = denied
            return
        }
        let asset = await VoiceCapture.ensureInstalled()
        if model.debugDriven { return }
        guard asset == .installed else {
            model.voiceStatus = asset.statusSentence
            return
        }
        model.voiceStatus = nil
        dictationBase = model.session.draft
        setDictating(true)
        beginCapture()
    }

    private func requestVoicePermission() async -> Bool {
        model.voicePermissionPrompt = true
        defer { model.voicePermissionPrompt = false }
        let mic = await VoicePermission.requestMicrophone()
        let speech = await VoicePermission.requestSpeech()
        return mic && speech
    }

    private func beginCapture() {
        if model.debugDriven { return }
        if let capture, capture.isRunning { return }
        capture?.stop()
        let session = VoiceCapture()
        session.onTranscript = { [weak self] text, isFinal in
            self?.handleTranscript(text, isFinal: isFinal)
        }
        session.onSpeechDetected = { [weak self] detected in
            self?.handleSpeechDetected(detected)
        }
        session.onFailure = { [weak self] message in
            self?.handleCaptureFailure(message)
        }
        capture = session
        session.start()
    }

    private func stopCapture() {
        capture?.stop()
        capture = nil
    }

    private func handleCaptureFailure(_ message: String) {
        if model.debugDriven { return }
        if model.dictating || model.voicePermissionPrompt {
            model.voiceStatus = message
        }
        setDictating(false)
        stopCapture()
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        if model.debugDriven { return }
        let recognized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recognized.isEmpty else { return }
        silentSince = Date()
        if model.dictating {
            applyDictation(recognized, isFinal: isFinal)
            return
        }
        guard store.wakeOnAxiom else { return }
        guard VoiceParser.wake(in: recognized) != nil else { return }
        let now = Date()
        if VoiceParser.cooldownBlocks(lastWake: lastWake, now: now) { return }
        lastWake = now
        silentSince = Date()
        openedFromWake = true
        openedAt = now
        dictationBase = panel.isVisible ? model.session.draft : ""
        show()
        setDictating(true)
        applyDictation(recognized, isFinal: isFinal)
        model.focusField()
    }

    private func applyDictation(_ recognized: String, isFinal: Bool) {
        let tail: String
        if openedFromWake, let wake = VoiceParser.wake(in: recognized) {
            tail = wake.remainder
        } else {
            tail = recognized
        }
        let applied = VoiceParser.applyTranscript(base: dictationBase, transcript: tail, isFinal: isFinal)
        dictationBase = applied.base
        model.setDraft(applied.display)
    }

    private func handleSpeechDetected(_ detected: Bool) {
        if detected {
            silentSince = nil
        } else if silentSince == nil {
            silentSince = Date()
        }
    }

    private func handleSendBegan() {
        endDictation(keepWakeCapture: true)
    }

    private func setDictating(_ on: Bool) {
        model.dictating = on
        if !on {
            dictationBase = ""
            silentSince = nil
        }
        model.onLayout()
    }

    private func endDictation(keepWakeCapture: Bool) {
        setDictating(false)
        openedFromWake = false
        openedAt = nil
        dictationBase = ""
        silentSince = nil
        if keepWakeCapture, store.wakeOnAxiom {
            return
        }
        stopCapture()
    }

    private func startVoicePolling() {
        voicePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.pollVoice()
            }
        }
    }

    private func pollVoice() {
        if model.debugDriven { return }
        let now = Date()
        let silentFor = silentSince.map { now.timeIntervalSince($0) } ?? 0
        let send = VoiceParser.shouldAutoSend(
            optionOn: store.pauseToSend,
            draft: model.session.draft,
            silentFor: silentFor,
            phase: model.session.phase,
            dictating: model.dictating
        )
        if send {
            model.submit()
        }
        if silentFor >= VoiceParser.emptyWakeHideAfter, let openedAt, VoiceParser.shouldHideEmptyWake(
            openedFromWake: openedFromWake,
            draft: model.session.draft,
            openedAt: openedAt,
            now: now
        ) {
            userDismiss(clickOutside: false)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        model.cardIsKey = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        (glass as? CardGlassView)?.containKeyFringe()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        model.cardIsKey = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let closingSettings = window == settingsWindow
        let closingDebug = window == debugWindow
        guard closingSettings || closingDebug else { return }
        let settingsOpen = !closingSettings && settingsWindow?.isVisible == true
        let debugOpen = !closingDebug && debugWindow?.isVisible == true
        if closingDebug {
            model.debugDriven = false
            startVoiceIfNeeded()
        }
        if !settingsOpen && !debugOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

final class ClickThroughHosting<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Keeps the window frame from painting a square behind the rounded plate.
final class CardGlassView: NSGlassEffectView {
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        containKeyFringe()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
        containKeyFringe()
    }

    func containKeyFringe() {
        applyClearRoundedMask(to: self)
        var node = superview
        while let view = node {
            applyClearRoundedMask(to: view)
            if view === window?.contentView {
                if let frameView = view.superview {
                    applyClearRoundedMask(to: frameView)
                }
                break
            }
            node = view.superview
        }
    }

    private func applyClearRoundedMask(to view: NSView) {
        view.wantsLayer = true
        view.focusRingType = .none
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

final class SolidCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = HUDMetrics.cornerRadius
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
