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
    private var pillViews: [HUDPillID: NSView] = [:]
    private var mountedNewUI = false
    var chrome: HUDChromeWrapper?
    private var lip: ErrorLipBand?
    private var settledCardHeight: CGFloat = HUDMetrics.minCardHeight
    private var layoutCard: CGFloat = HUDMetrics.minCardHeight
    private var layoutHasLip = false
    /// Keeps the lip on screen for the shrink that follows a dismiss, so it slides back under the plate.
    private var retractingLip = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var menuBegin: NSObjectProtocol?
    private var menuEnd: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var activationObservers: [NSObjectProtocol] = []
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
        // Any focus change can move you into or out of Settings, its sheet, or its popover.
        for name in [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification
        ] {
            activationObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restackAuxiliaryWindows() }
            })
        }
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
                multiline: model.displayedMultiline,
                minimum: store.usesNewUI ? HUDMetrics.rowHeight : HUDMetrics.minCardHeight
            )
            settledCardHeight = card
            panel.centerOnMouseScreen(
                height: HUDSplitChromeLayout.panelHeight(
                    splitEnabled: store.usesNewUI,
                    settledCapsuleHeight: card,
                    hasLip: model.lipMessage != nil
                )
            )
            syncFrame(animated: false)
            if store.usesNewUI {
                chrome?.beginPour(opening: true)
            }
        } else if panel.isFadingOut, store.usesNewUI {
            // Shown again mid-dismiss: turn the pills around from where they are.
            chrome?.beginPour(opening: true)
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
        if store.usesNewUI {
            chrome?.beginPour(opening: false)
            panel.fadeOut(delay: HUDFrameMotion.pourDismissFadeDelay) { }
        } else {
            panel.fadeOut { }
        }
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
        // Both mounts make the chrome the content view, so ask which plate it holds.
        let showingSolid = solid != nil && chrome?.plate === solid
        if panel.contentView == nil || wantSolid != showingSolid || mountedNewUI != store.usesNewUI {
            mount(hosting)
            mountedNewUI = store.usesNewUI
            syncFrame(animated: false)
            // The region swap builds a new prompt editor. Settle it now so focus reaches the live one.
            hosting.layoutSubtreeIfNeeded()
            if panel.isVisible {
                DispatchQueue.main.async { [weak self] in
                    self?.model.focusField()
                }
            }
            return
        }
        if !wantSolid {
            if store.usesNewUI {
                if let glass {
                    (glass as? CardGlassView)?.masksAncestors = false
                    applyGlass(
                        glass,
                        cornerRadius: HUDSplitChromeLayout.capsuleCornerRadius(height: chrome?.splitCapsuleHeight ?? HUDMetrics.rowHeight)
                    )
                }
                for case let pill as NSGlassEffectView in pillViews.values {
                    applyGlass(pill, cornerRadius: HUDSplitChromeLayout.pillHeight / 2)
                }
            } else {
                applyGlass(glass ?? CardGlassView())
            }
        }
    }

    private func refreshPressHighlights() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let canSend = model.session.canSend || model.captureArmed || model.session.showsStop
        for (id, view) in pillViews {
            guard let pill = view as? PillGlassView else { continue }
            switch id {
            case .send:
                pill.pressHighlight = canSend
            case .shortcut:
                pill.pressHighlight = store.savesHistory
            default:
                pill.pressHighlight = true
            }
            if #available(macOS 27.0, *) {
                pill.effectIsInteractive = pill.pressHighlight && !reduce
            }
        }
    }

    private func applyGlass(_ glassView: NSGlassEffectView, cornerRadius: CGFloat = HUDMetrics.cornerRadius) {
        let style = HUDMaterial.effectStyle(matte: store.usesMatte)
        glassView.style = style == .regular ? .regular : .clear
        glassView.cornerRadius = cornerRadius
        let veil = HUDMaterial.veilOpacity(glassAmount: store.glassAmount)
        glassView.tintColor = veil == 0 ? nil : NSColor.windowBackgroundColor.withAlphaComponent(veil)
        if #available(macOS 27.0, *) {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            // Only pills press. The card is a text surface, not a button.
            let interactive = !reduce && ((glassView as? PillGlassView)?.pressHighlight ?? false)
            glassView.effectIsInteractive = interactive
        }
        // Regular glass is opaque, so the window shadow becomes a black box while the panel is key.
        panel.hasShadow = style != .regular
        panel.invalidateShadow()
        if let card = glassView as? CardGlassView, card.masksAncestors {
            card.containKeyFringe()
        }
    }

    private func mount(_ hosting: NSView) {
        let anchor = promptAnchor ?? PromptAnchorView(host: hosting)
        promptAnchor = anchor
        // Setting the same contentView again is a no-op, so the glass would stay empty after a remount.
        glass?.contentView = nil
        anchor.removeFromSuperview()
        let chrome = self.chrome ?? HUDChromeWrapper(
            frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
        )
        self.chrome = chrome
        let lip = self.lip ?? ErrorLipBand(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDLayout.lipHeight))
        self.lip = lip
        if store.usesNewUI {
            mountSplit(anchor: anchor, hosting: hosting, chrome: chrome, lip: lip)
            mountedNewUI = true
            return
        }
        mountedNewUI = false
        removeSplitPills()
        panel.chromeMargin = NSEdgeInsetsZero
        chrome.margin = NSEdgeInsetsZero
        self.hosting?.rootView = HUDView(model: model, store: store, region: .plate)
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
            (glassView as? CardGlassView)?.masksAncestors = true
            applyGlass(glassView)
            glassView.contentView = anchor
            let container = glassContainer ?? HUDGlassContainer(
                frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
            )
            glassContainer = container
            container.spacing = HUDMaterial.glassContainerSpacing
            (container as? HUDGlassContainer)?.passesThroughGaps = false
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

    private func mountSplit(
        anchor: PromptAnchorView,
        hosting: NSView,
        chrome: HUDChromeWrapper,
        lip: ErrorLipBand
    ) {
        self.hosting?.rootView = HUDView(model: model, store: store, region: .capsule)
        removeSplitPills()
        chrome.usesSplit = true
        panel.chromeMargin = HUDSplitChromeLayout.windowMargin
        chrome.margin = HUDSplitChromeLayout.windowMargin
        let wantSolid = HUDMaterial.usesSolidCard(reduceTransparency: reduceTransparency)
        if wantSolid {
            let card = solid ?? SolidCardView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.rowHeight))
            solid = card
            card.embed(anchor)
            glass?.contentView = nil
            glass?.removeFromSuperview()
            glassContainer?.contentView = nil
            chrome.plate = card
            panel.contentView = chrome
        } else {
            let glassView = glass ?? CardGlassView(frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.rowHeight))
            glass = glassView
            (glassView as? CardGlassView)?.masksAncestors = false
            applyGlass(
                glassView,
                cornerRadius: HUDSplitChromeLayout.capsuleCornerRadius(height: HUDMetrics.rowHeight)
            )
            glassView.contentView = anchor
            let container = (glassContainer as? HUDGlassContainer) ?? HUDGlassContainer(
                frame: NSRect(x: 0, y: 0, width: HUDMetrics.cardWidth, height: HUDMetrics.minCardHeight)
            )
            glassContainer = container
            container.passesThroughGaps = true
            container.spacing = HUDMaterial.glassContainerSpacing
            solid?.removeFromSuperview()
            chrome.plate = glassView
            chrome.wantsLayer = true
            chrome.layer?.isOpaque = false
            chrome.layer?.backgroundColor = NSColor.clear.cgColor
            chrome.layer?.cornerRadius = 0
            chrome.layer?.masksToBounds = false
            chrome.layer?.mask = nil
            chrome.autoresizingMask = [.width, .height]
            container.contentView = chrome
            panel.contentView = container
        }
        chrome.lip = lip
        chrome.embedPlateAndLip()
        chrome.layer?.cornerRadius = 0
        chrome.layer?.masksToBounds = false
        chrome.layer?.mask = nil
        clipHosting(hosting)
        hosting.layer?.cornerRadius = HUDSplitChromeLayout.capsuleCornerRadius(height: HUDMetrics.rowHeight)
        anchor.clipsToBounds = true
        syncSplitPills()
    }

    private func syncSplitPills() {
        guard store.usesNewUI, let chrome else { return }
        let columns = HUDPillID.columns(
            showsPreset: store.showsPresetControl
        )
        let wantSolid = HUDMaterial.usesSolidCard(reduceTransparency: reduceTransparency)
        let live = columns.leading + columns.trailing
        let removed = pillViews.keys.filter { !live.contains($0) }
        for id in removed {
            if let view = pillViews[id] {
                chrome.retirePill(view)
            }
            pillViews.removeValue(forKey: id)
        }
        func holder(for id: HUDPillID) -> NSView {
            if let existing = pillViews[id] { return existing }
            let host = ClickThroughHosting(
                rootView: HUDView(model: model, store: store, region: .pill(id))
            )
            host.safeAreaRegions = []
            let view: NSView
            if wantSolid {
                let pill = SolidPillView(frame: .zero)
                pill.embed(host)
                view = pill
            } else {
                let pill = PillGlassView(frame: .zero)
                applyGlass(pill, cornerRadius: HUDSplitChromeLayout.pillHeight / 2)
                pill.contentView = host
                view = pill
            }
            chrome.addSubview(view)
            pillViews[id] = view
            return view
        }
        let existed = !pillViews.isEmpty
        let inserted = live.contains { pillViews[$0] == nil }
        chrome.splitLeading = columns.leading.map(holder)
        chrome.splitTrailing = columns.trailing.map(holder)
        if existed, !removed.isEmpty || inserted, !chrome.isPouring {
            chrome.beginPillSlide()
            panel.beginChromeTick()
        }
    }

    private func removeSplitPills() {
        for view in pillViews.values {
            view.removeFromSuperview()
        }
        pillViews.removeAll()
        chrome?.cancelPillSlide()
        chrome?.cancelPour()
        chrome?.splitLeading = []
        chrome?.splitTrailing = []
        chrome?.usesSplit = false
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
        let region: HUDChromeRegion = store.usesNewUI ? .capsule : .plate
        let probe = HUDView(model: model, store: store, measuresOnly: true, region: region)
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
            historyExpanded: model.historyExpanded,
            toolLine: model.toolLine
        )
        let paddedCap = showsReply
            ? baseCap + HUDLayout.replyScrollVerticalPadding
            : baseCap
        if store.usesNewUI {
            let floor = HUDMetrics.rowHeight
            return min(max(floor, fitted), max(floor, paddedCap))
        }
        let capped = min(max(HUDMetrics.minCardHeight, fitted), paddedCap)
        return HUDLayout.cardHeight(fittingHeight: capped)
    }

    /// Prompt/toolbar/chips floor. Expanded history must not treat the unrolled thread as chrome.
    private func estimatedChromeHeight(fitted: CGFloat) -> CGFloat {
        let floor = store.usesNewUI ? HUDMetrics.rowHeight : HUDMetrics.minCardHeight
        if model.historyExpanded {
            var chromeHeight = floor
            if model.displayedMultiline, model.promptLineCount > 1 {
                let line = PromptLayout.promptLineHeight
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
            historyExpanded: model.historyExpanded,
            toolLine: model.toolLine
        )
        if showsReply, visible > 0 {
            let region = HUDLayout.replyBodyHeight(lines: visible) + HUDLayout.replyScrollVerticalPadding
            return max(floor, fitted - region)
        }
        return max(floor, fitted)
    }

    private func syncFrame(animated: Bool = false) {
        let fitted = measuredHeight()
        let chromeHeight = estimatedChromeHeight(fitted: fitted)
        let card = HUDLayout.settledHeight(
            proposed: fitted,
            previous: settledCardHeight,
            lineCount: model.promptLineCount,
            multiline: model.displayedMultiline,
            minimum: store.usesNewUI ? HUDMetrics.rowHeight : HUDMetrics.minCardHeight
        )
        settledCardHeight = card
        let message = model.lipMessage
        let hasLip = message != nil
        let height = HUDSplitChromeLayout.panelHeight(
            splitEnabled: store.usesNewUI,
            settledCapsuleHeight: card,
            hasLip: hasLip
        )
        let answerLines = HUDLayout.wrappedReplyLines(model.session.displayAnswer)
        let growthLines = HUDLayout.replyGrowthLines(
            answerLines: answerLines,
            historyExpanded: model.historyExpanded
        )
        var growthChrome = chromeHeight
        if store.usesNewUI {
            growthChrome += HUDSplitChromeLayout.pillGap + HUDSplitChromeLayout.pillHeight
        }
        if hasLip {
            growthChrome += HUDLayout.lipVisible
        }
        let showsReply = HistoryChromePolicy.showsReplyRegion(
            answer: model.session.displayAnswer,
            phase: model.session.phase,
            historyExpanded: model.historyExpanded,
            toolLine: model.toolLine
        )
        if showsReply {
            growthChrome += HUDLayout.replyScrollVerticalPadding
        }
        if hasLip {
            retractingLip = false
        } else if layoutHasLip {
            retractingLip = true
        }
        if store.usesNewUI, animated, chrome?.isPouring == true, abs((chrome?.splitCapsuleHeight ?? card) - card) > 0.5 {
            chrome?.handoffPourToGrowth()
        }
        panel.resizeForReply(
            to: height,
            replyLines: growthLines,
            chromeHeight: growthChrome,
            targetCapsule: store.usesNewUI ? card : nil,
            shownCapsule: store.usesNewUI ? (chrome?.splitCapsuleHeight ?? card) : nil,
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
        // Views fill the window, margin included. Card heights below stay in card space.
        let windowBounds = NSRect(origin: .zero, size: panel.frame.size)
        if !panel.isAnimatingFrame {
            retractingLip = false
        }
        let showLip = hasLip || retractingLip
        let reveal = HUDLayout.lipPlacement(
            windowHeight: panel.cardFrame.height,
            cardHeight: card,
            cardWidth: HUDMetrics.cardWidth,
            hasLip: showLip
        ).revealed
        chrome?.usesSplit = store.usesNewUI
        chrome?.hasLip = showLip
        if store.usesNewUI {
            syncSplitPills()
            chrome?.splitCapsuleHeight = panel.displayedCapsuleHeight(fallback: card)
            refreshPressHighlights()
            let displayed = panel.displayedCapsuleHeight(fallback: card)
            let extra = max(0, model.promptLineCount - 1)
            model.splitChipOpacity = model.session.chips.isEmpty
                ? 1
                : HUDSplitChromeLayout.chipOpacity(
                    displayedCapsule: displayed,
                    promptBlock: HUDSplitChromeLayout.promptBlock(extraLines: extra)
                )
        } else if panel.isAnimatingFrame {
            chrome?.cardHeight = max(card, panel.cardFrame.height - reveal)
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
            keyCode: event.keyCode,
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            panelIsKey: panel.isVisible && panel.isKeyWindow,
            menuTracking: panel.menuTracking,
            hasAttachedSheet: panel.attachedSheet != nil,
            isComposing: panel.isComposingInput,
            bindings: CardShortcutBindings.current()
        ) else {
            return false
        }
        switch shortcut {
        case .hide:
            return false
        case .send:
            model.submit()
        case .newline:
            model.insertLineBreak()
        case .cyclePreset:
            guard store.showsPresetControl else { return true }
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
        if panel.frame.contains(point) {
            if store.usesNewUI, let chrome {
                let local = chrome.convert(panel.convertPoint(fromScreen: point), from: nil)
                if chrome.pointHitsSplitChrome(local) { return }
                userDismiss(clickOutside: true)
            }
            return
        }
        if let statusFrame = statusItemFrame, statusFrame.contains(point) { return }
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
                    model.reportScreenFailure(.failed)
                    return
                }
                model.beginSend(
                    jpeg: jpeg,
                    name: target.title,
                    highlightFrame: result.highlightFrame
                )
            } catch let error as ScreenGrabError {
                model.reportScreenFailure(error)
            } catch {
                model.reportScreenFailure(.failed)
            }
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
            hosting?.rootView = HUDView(
                model: model,
                store: store,
                region: store.usesNewUI ? .capsule : .plate
            )
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

    /// The card floats, so a normal window opens behind it. The auxiliary window you are using rises
    /// to the card's level, and ordering it front puts it over the card. It drops back when you leave it.
    func restack(_ window: NSWindow) {
        let level = AuxiliaryWindowLevel.level(
            appActive: NSApp.isActive,
            isKey: window.isKeyWindow,
            ownsFocus: window.attachedSheet != nil || !(window.childWindows ?? []).isEmpty,
            cardLevel: panel.level
        )
        guard window.level != level else { return }
        window.level = level
        if level != .normal {
            window.orderFront(nil)
        }
    }

    func restackAuxiliaryWindows() {
        for window in [settingsWindow, debugWindow, transcriptWindow].compactMap({ $0 }) where window.isVisible {
            restack(window)
        }
    }

}

