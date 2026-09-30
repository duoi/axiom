import AppKit
import SwiftUI

@MainActor
final class HUDController: NSObject, NSWindowDelegate {
    let panel = HUDPanel()
    let model: HUDModel
    let store: EndpointStore

    private var hosting: ClickThroughHosting<HUDView>?
    private var promptAnchor: PromptAnchorView?
    /// Offscreen. The on-screen host must never be resized to the 10_000pt measure.
    private var measurementHost: ClickThroughHosting<HUDView>?
    private var glass: NSGlassEffectView?
    private var glassContainer: NSGlassEffectContainerView?
    private var solid: SolidCardView?
    var chrome: HUDChromeWrapper?
    private var lip: ErrorLipBand?
    private var settledCardHeight: CGFloat = HUDMetrics.minCardHeight
    private var layoutCard: CGFloat = HUDMetrics.minCardHeight
    private var layoutHasLip = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var menuBegin: NSObjectProtocol?
    private var menuEnd: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    var settingsWindow: NSWindow?
    var debugWindow: NSWindow?
    var transcriptWindow: NSWindow?
    private var reduceTransparency = false
    var capture: VoiceCapture?
    var lastWake: Date?
    var dictationBase = ""
    var openedFromWake = false
    var openedAt: Date?
    var silentSince: Date?
    var voicePoll: Task<Void, Never>?

    init(store: EndpointStore) {
        self.store = store
        self.model = HUDModel(store: store)
        super.init()
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onAddContext = { [weak self] in self?.addContext() }
        model.onCaptureScreen = { [weak self] in self?.captureForSend() }
        model.onLayout = { [weak self] in
            guard let self else { return }
            self.syncFrame(animated: self.panel.isVisible && !self.panel.isFadingOut)
        }
        panel.onFrameStep = { [weak self] in
            self?.layoutChrome()
        }
        model.onToggleDictation = { [weak self] in self?.toggleDictation() }
        model.onSetWake = { [weak self] on in self?.setWake(on) }
        model.onSendBegan = { [weak self] in self?.handleSendBegan() }
        store.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        DebugPreviewStore.shared.setDebugEnabled(
            HUDCardMenu.debugEnabled(arguments: CommandLine.arguments, defaults: .standard)
        )
        DebugPreviewStore.shared.onChange = { [weak self] in
            self?.refreshActiveGlow()
        }
        panel.onCancel = { [weak self] in self?.userDismiss(clickOutside: false) }
        panel.delegate = self
        installChrome()
        installMonitors()
        startVoicePolling()
    }

    func toggle() {
        if panel.isVisible && !panel.isFadingOut {
            userDismiss(clickOutside: false)
        } else {
            show()
        }
    }

    func show() {
        if panel.isVisible && !panel.isFadingOut {
            panel.orderFrontRegardless()
            panel.makeKey()
            DispatchQueue.main.async { [weak self] in
                self?.model.focusField()
            }
            return
        }
        if !panel.isVisible {
            rebuildChromeIfNeeded()
            let card = HUDLayout.settledHeight(
                proposed: measuredHeight(),
                previous: settledCardHeight,
                lineCount: model.promptLineCount,
                multiline: model.displayedMultiline
            )
            settledCardHeight = card
            panel.centerOnMouseScreen(
                height: HUDLayout.windowHeight(card: card, hasLip: model.lipMessage != nil)
            )
            syncFrame(animated: false)
        }
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
        model.persistHistoryIfNeeded()
        model.cancelForQuit()
    }

    func startVoiceIfNeeded() {
        guard store.wakeOnAxiom, !model.debugDriven else { return }
        Task { await startWakeCapture(prompt: false) }
    }

    func userDismiss(clickOutside: Bool) {
        guard model.dismiss(clickOutside: clickOutside) else { return }
        endDictation(keepWakeCapture: true)
        CaptureHighlight.hidePersistent()
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
            // A click flexes this 560-point plate.
            glassView.effectIsInteractive = false
        }
        // Regular glass is opaque, so the window shadow becomes a black box while the panel is key.
        panel.hasShadow = style != .regular
        panel.invalidateShadow()
        (glassView as? CardGlassView)?.containKeyFringe()
    }

    private func mount(_ hosting: NSView) {
        let anchor = promptAnchor ?? PromptAnchorView(host: hosting)
        promptAnchor = anchor
        anchor.removeFromSuperview()
        let chrome = self.chrome ?? HUDChromeWrapper(
            frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
        )
        self.chrome = chrome
        let lip = self.lip ?? ErrorLipBand(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDLayout.lipHeight))
        self.lip = lip
        if HUDMaterial.usesSolidCard(reduceTransparency: reduceTransparency) {
            let card = solid ?? SolidCardView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight))
            solid = card
            card.embed(anchor)
            glass?.contentView = nil
            glassContainer?.contentView = nil
            glass?.removeFromSuperview()
            chrome.plate = card
            chrome.lip = lip
            chrome.embedPlateAndLip()
            chrome.autoresizingMask = []
            panel.contentView = chrome
        } else {
            let glassView = glass ?? CardGlassView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight))
            glass = glassView
            applyGlass(glassView)
            glassView.contentView = anchor
            let container = glassContainer ?? NSGlassEffectContainerView(
                frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
            )
            glassContainer = container
            container.spacing = HUDMaterial.glassContainerSpacing
            solid?.removeFromSuperview()
            chrome.plate = glassView
            chrome.lip = lip
            chrome.embedPlateAndLip()
            chrome.wantsLayer = true
            chrome.layer?.isOpaque = false
            chrome.layer?.backgroundColor = NSColor.clear.cgColor
            chrome.autoresizingMask = [.width, .height]
            container.contentView = chrome
            panel.contentView = container
        }
        clipHosting(hosting)
        anchor.clipsToBounds = true
    }

    private func clipHosting(_ hosting: NSView) {
        hosting.wantsLayer = true
        hosting.clipsToBounds = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = HUDMetrics.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
    }

    private func measuredHeight() -> CGFloat {
        guard let hosting else { return HUDLayout.cardHeight() }
        hosting.rootView = HUDView(model: model, store: store)
        let probe = HUDView(model: model, store: store, measuresOnly: true)
        let measurer = measurementHost ?? ClickThroughHosting(rootView: probe)
        measurementHost = measurer
        measurer.safeAreaRegions = []
        measurer.rootView = probe
        measurer.setFrameSize(HUDLayout.hostingFitSize)
        measurer.invalidateIntrinsicContentSize()
        measurer.layoutSubtreeIfNeeded()
        let fitted = measurer.fittingSize.height
        let chromeHeight = estimatedChromeHeight(fitted: fitted)
        let baseCap = HUDLayout.cappedCardHeight(proposed: fitted, chromeHeight: chromeHeight)
        let showsReply = HistoryChromePolicy.showsReplyRegion(
            answer: model.session.displayAnswer,
            phase: model.session.phase,
            historyExpanded: model.historyExpanded
        )
        let paddedCap = showsReply
            ? baseCap + HUDLayout.replyScrollVerticalPadding
            : baseCap
        let capped = min(max(HUDMetrics.minCardHeight, fitted), paddedCap)
        return HUDLayout.cardHeight(fittingHeight: capped)
    }

    /// Prompt/toolbar/chips floor. Expanded history must not treat the unrolled thread as chrome.
    private func estimatedChromeHeight(fitted: CGFloat) -> CGFloat {
        if model.historyExpanded {
            var chromeHeight = HUDMetrics.minCardHeight
            if model.displayedMultiline, model.promptLineCount > 1 {
                let line = PromptLayout.lineHeight(for: PromptLayout.font())
                chromeHeight += CGFloat(model.promptLineCount - 1) * line
            }
            if !model.session.chips.isEmpty {
                chromeHeight += HUDMetrics.rowHeight / 2
            }
            return chromeHeight
        }
        let answerLines = HUDLayout.wrappedReplyLines(model.session.displayAnswer)
        let visible = HUDLayout.replyVisibleLines(answerLines)
        let showsReply = HistoryChromePolicy.showsReplyRegion(
            answer: model.session.displayAnswer,
            phase: model.session.phase,
            historyExpanded: model.historyExpanded
        )
        if showsReply, visible > 0 {
            let region = HUDLayout.replyBodyHeight(lines: visible) + HUDLayout.replyScrollVerticalPadding
            return max(HUDMetrics.minCardHeight, fitted - region)
        }
        return max(HUDMetrics.minCardHeight, fitted)
    }

    private func syncFrame(animated: Bool = false) {
        let fitted = measuredHeight()
        let chromeHeight = estimatedChromeHeight(fitted: fitted)
        let card = HUDLayout.settledHeight(
            proposed: fitted,
            previous: settledCardHeight,
            lineCount: model.promptLineCount,
            multiline: model.displayedMultiline
        )
        settledCardHeight = card
        let message = model.lipMessage
        let hasLip = message != nil
        let height = HUDLayout.windowHeight(card: card, hasLip: hasLip)
        let answerLines = HUDLayout.wrappedReplyLines(model.session.displayAnswer)
        let growthLines = HUDLayout.replyGrowthLines(
            answerLines: answerLines,
            historyExpanded: model.historyExpanded
        )
        var growthChrome = chromeHeight
        if hasLip {
            growthChrome += HUDLayout.lipVisible
        }
        let showsReply = HistoryChromePolicy.showsReplyRegion(
            answer: model.session.displayAnswer,
            phase: model.session.phase,
            historyExpanded: model.historyExpanded
        )
        if showsReply {
            growthChrome += HUDLayout.replyScrollVerticalPadding
        }
        panel.resizeForReply(
            to: height,
            replyLines: growthLines,
            chromeHeight: growthChrome,
            animated: animated
        )
        layoutCard = card
        layoutHasLip = hasLip
        layoutChrome()
        if let message {
            lip?.apply(
                message,
                onTap: { [weak self] in self?.handleLipTap(message.action) },
                onDismiss: { [weak self] in self?.model.dismissLip() }
            )
        }
        syncDictationGlow()
    }

    /// Plate tracks the live window rect. Content stays on the pinned edge while the frame eases.
    private func layoutChrome() {
        let card = layoutCard
        let hasLip = layoutHasLip
        let windowBounds = NSRect(
            origin: .zero,
            size: NSSize(width: HUDMetrics.cardWidth, height: panel.frame.height)
        )
        chrome?.hasLip = hasLip
        if panel.isAnimatingFrame {
            let lip = hasLip ? HUDLayout.lipVisible : 0
            chrome?.cardHeight = max(card, panel.frame.height - lip)
        } else {
            chrome?.cardHeight = card
        }
        chrome?.frame = windowBounds
        glassContainer?.frame = windowBounds
        panel.contentView?.frame = windowBounds
        chrome?.needsLayout = true
        chrome?.layoutSubtreeIfNeeded()
        promptAnchor?.needsLayout = true
        promptAnchor?.layoutSubtreeIfNeeded()
        if panel.isAnimatingFrame {
            refreshActiveGlow()
        }
    }


    private func handleLipTap(_ action: HUDErrorLip.Action) {
        switch action {
        case .voice:
            model.openVoiceSettings()
        case .screen:
            model.openScreenSettings()
        case .accessibility:
            model.openAccessibilitySettings()
        case .none:
            break
        }
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.clickOutside(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                MainActor.assumeIsolated {
                    self.clickOutside(event)
                }
                return event
            case .rightMouseDown:
                var consume = false
                var location = NSPoint.zero
                MainActor.assumeIsolated {
                    consume = event.window === self.panel
                        && self.panel.isVisible
                        && !self.panel.menuTracking
                    if consume {
                        location = event.locationInWindow
                    }
                }
                guard consume else { return event }
                DispatchQueue.main.async { [weak self] in
                    self?.popCardMenu(at: location)
                }
                return nil
            case .keyDown:
                var handled = false
                MainActor.assumeIsolated {
                    handled = self.panel.handleEscapeEvent(event) || self.handleCardShortcut(event)
                }
                return handled ? nil : event
            default:
                return event
            }
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

    private func popCardMenu(at locationInWindow: NSPoint) {
        guard panel.isVisible, !panel.menuTracking else { return }
        let debugOn = HUDCardMenu.debugEnabled(
            arguments: CommandLine.arguments,
            defaults: .standard
        )
        let proxy = CardMenuProxy(
            onSettings: { [weak self] in self?.openSettings() },
            onDebug: { [weak self] in self?.openDebug() }
        )
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in HUDCardMenu.items(debugEnabled: debugOn) {
            let row = NSMenuItem(
                title: HUDCardMenu.title(for: item),
                action: item == .settings
                    ? #selector(CardMenuProxy.openSettings)
                    : #selector(CardMenuProxy.openDebug),
                keyEquivalent: ""
            )
            row.target = proxy
            row.isEnabled = true
            menu.addItem(row)
        }
        guard let view = panel.contentView else { return }
        let point = view.convert(locationInWindow, from: nil)
        withExtendedLifetime(proxy) {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    private func handleCardShortcut(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let shortcut = HUDShortcuts.action(
            characters: event.charactersIgnoringModifiers,
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            panelIsKey: panel.isVisible && panel.isKeyWindow,
            menuTracking: panel.menuTracking,
            hasAttachedSheet: panel.attachedSheet != nil
        ) else {
            return false
        }
        switch shortcut {
        case .cyclePreset:
            model.setPreset(model.session.preset == .agent ? .ask : .agent)
        case .cycleCapture:
            model.cycleCaptureShortcut()
        case .addContext:
            addContext()
        case .toggleIncognito:
            model.toggleHistoryExclusion()
        case .toggleDictation:
            model.toggleDictation()
        }
        return true
    }

    private func clickOutside(_ event: NSEvent) {
        guard panel.isVisible else { return }
        if model.voicePermissionPrompt { return }
        if store.keepHovering { return }
        if panel.menuTracking || menuWindowIsOpen || panel.attachedSheet != nil { return }
        if settingsWindow?.isVisible == true { return }
        if let window = event.window {
            if window === panel || window === settingsWindow || window === debugWindow || window === transcriptWindow {
                return
            }
            let name = String(describing: type(of: window))
            if name.contains("Menu") { return }
        }
        let point = screenPoint(of: event)
        if panel.frame.contains(point) { return }
        if let statusFrame = statusItemFrame, statusFrame.contains(point) { return }
        if let settings = settingsWindow, settings.isVisible, settings.frame.contains(point) { return }
        if let debug = debugWindow, debug.isVisible, debug.frame.contains(point) { return }
        if let transcript = transcriptWindow, transcript.isVisible, transcript.frame.contains(point) { return }
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
        let target = model.displayedCaptureTarget
        let hides = CapturePanelConceal.hidesPanel(target: target)
        if hides {
            panel.concealForCapture()
            CATransaction.flush()
        }
        Task { @MainActor in
            do {
                let result = try await ScreenGrab.capture(
                    excluding: windowID,
                    displayID: displayID,
                    frontPID: frontPID,
                    target: target
                )
                let jpeg = ScreenImage.jpeg(from: result.image)
                guard !jpeg.isEmpty else {
                    if hides { self.revealAfterCapture() }
                    model.reportScreenFailure(.failed)
                    return
                }
                model.beginSend(
                    jpeg: jpeg,
                    name: target.title,
                    highlightFrame: result.highlightFrame
                )
                if hides { self.revealAfterCapture() }
            } catch let error as ScreenGrabError {
                if hides { self.revealAfterCapture() }
                model.reportScreenFailure(error)
            } catch {
                if hides { self.revealAfterCapture() }
                model.reportScreenFailure(.failed)
            }
        }
    }

    private func revealAfterCapture() {
        panel.reveal()
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


    func applyDebugCommand(_ command: String) {
        let plan = DebugRouting.plan(command: command, snapshot: model.debugSnapshot())
        let preview = DebugPreviewStore.shared
        if let shimmer = plan.shimmer {
            preview.shimmerStyle = shimmer
        }
        switch plan.kind {
        case .openTranscript:
            openTranscript()
        case .flashHighlight:
            if !panel.isVisible {
                show()
            }
            flashHUDGlow()
        case .liveStream(let text, let finish):
            if !panel.isVisible {
                show()
            }
            model.simulateIncomingStream(text, finish: finish)
            syncFrame(animated: true)
        case .apply(let next):
            model.apply(next)
            hosting?.rootView = HUDView(model: model, store: store)
            if !panel.isVisible {
                show()
            }
            syncDictationGlow()
            if next.wantsCardKey == true {
                panel.makeKey()
                DispatchQueue.main.async { [weak self] in
                    self?.model.focusField()
                }
            } else if next.wantsCardKey == false {
                debugWindow?.makeKey()
            }
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

}

