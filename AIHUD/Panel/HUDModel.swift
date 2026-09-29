import AppKit
import AVFoundation
import CoreGraphics
import Observation
import Speech

@MainActor
@Observable
final class HUDModel {
    var session = Session()
    var stickToBottom = true
    weak var promptEditor: (any PromptEditing)?

    let store: EndpointStore
    var onOpenSettings: () -> Void = {}
    var onAddContext: () -> Void = {}
    var onCaptureScreen: () -> Void = {}
    var onLayout: () -> Void = {}
    var historyExpanded = false
    var historyExcluded = false
    var screenNotice: String? {
        didSet {
            if screenNotice != oldValue {
                if screenNotice != nil {
                    lipDismissed = false
                }
                onLayout()
            }
        }
    }
    var captureArmed = false
    var cardIsKey = true
    var reduceTransparency = false
    var dictating = false
    var voiceStatus: String? {
        didSet {
            if voiceStatus != oldValue {
                if voiceStatus != nil {
                    lipDismissed = false
                }
                onLayout()
            }
        }
    }
    var lipDismissed = false
    var voicePermissionPrompt = false
    var onToggleDictation: () -> Void = {}
    var onSetWake: (Bool) -> Void = { _ in }
    var onSendBegan: () -> Void = {}
    var debugDriven = false
    var promptLineCount = 1
    var logoOverride: ProviderLogoKind?
    var captureTargetOverride: CaptureTarget?
    var multilineOverride: Bool?

    var lipMessage: HUDErrorLip.Message? {
        HUDErrorLip.message(
            phase: session.phase,
            blockingMessage: store.blockingMessage,
            screenNotice: screenNotice,
            voiceStatus: voiceStatus,
            dismissed: lipDismissed
        )
    }

    var displayedCaptureTarget: CaptureTarget {
        captureTargetOverride ?? store.captureTarget
    }

    var displayedMultiline: Bool {
        multilineOverride ?? store.usesMultilinePrompt
    }

    var pillIsMatte: Bool {
        HUDMaterial.pillIsMatte(
            preference: store.usesMatte,
            reduceTransparency: reduceTransparency,
            cardIsKey: cardIsKey
        )
    }

    private var task: Task<Void, Never>?
    private var clientSession: URLSession?
    private var redirectGuard: RedirectGuard?

    init(store: EndpointStore) {
        self.store = store
    }

    func simulateIncomingStream(_ text: String, finish: Bool = true) {
        cancelForQuit()
        debugDriven = true
        lipDismissed = false
        historyExpanded = false
        stickToBottom = true
        session = DebugRouting.apply("waiting", to: Session())
        pushDraftToField("")
        onLayout()
        for chunk in DebugRouting.streamChunks(text) {
            var streaming = session
            streaming.receiveToken(chunk)
            session = streaming
            onLayout()
        }
        guard finish else { return }
        var done = session
        done.finish()
        session = done
        persistHistoryIfNeeded()
        onLayout()
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            session: session,
            captureArmed: captureArmed,
            dictating: dictating,
            voiceStatus: voiceStatus,
            screenNotice: screenNotice,
            logoOverride: logoOverride,
            captureTargetOverride: captureTargetOverride,
            multilineOverride: multilineOverride,
            historyExpanded: historyExpanded
        )
    }

    func apply(_ snapshot: DebugSnapshot) {
        debugDriven = true
        cancelForQuit()
        lipDismissed = false
        session = snapshot.session
        captureArmed = snapshot.captureArmed
        dictating = snapshot.dictating
        voiceStatus = snapshot.voiceStatus
        screenNotice = snapshot.screenNotice
        logoOverride = snapshot.logoOverride
        captureTargetOverride = snapshot.captureTargetOverride
        multilineOverride = snapshot.multilineOverride
        historyExpanded = snapshot.historyExpanded
        pushDraftToField(session.draft)
        onLayout()
    }

    func applyDebugLogoAsChat() {
        guard let logo = logoOverride else { return }
        let current = ChatModelSelection(
            chatID: store.defaultEndpointID,
            chatModelID: store.chatModelID,
            visionID: store.visionEndpointID,
            visionModelID: store.visionModelID
        )
        guard let pick = DebugChatApply.readyPick(
            logo: logo,
            endpoints: store.endpoints,
            current: current,
            secret: { store.apiKey(for: $0) },
            onDeviceReady: OnDeviceChat.availability == .available
        ), let providerID = pick.chatID else {
            return
        }
        store.selectChat(
            providerID: providerID,
            modelID: pick.chatModelID
        )
        onLayout()
    }

    func setDraft(_ text: String) {
        guard PromptInFlightPolicy.isEditable(phase: session.phase) else { return }
        session.draft = text
        pushDraftToField(text)
        if displayedMultiline {
            onLayout()
        }
    }

    func pushDraftToField(_ text: String) {
        promptEditor?.applyPrompt(text)
    }

    func setPreset(_ preset: Preset) {
        session.preset = preset
    }

    func removeChip(_ id: UUID) {
        session.chips.removeAll { $0.id == id }
        onLayout()
    }

    func addChip(_ chip: Chip) {
        session.chips.append(chip)
        session.errorMessage = nil
        if case .failed = session.phase {
            session.phase = .composing
        }
        onLayout()
    }

    func reportAttachmentError(_ error: AttachmentError) {
        lipDismissed = false
        let message: String
        switch error {
        case .tooMany: message = "You can attach up to \(AttachmentPolicy.maxFiles) files."
        case .tooLarge: message = "That file is larger than 4 MB."
        case .binary: message = "That file is not text."
        case .unsupported: message = "That file type is not supported."
        case .unreadableImage: message = "That image could not be read."
        }
        session.errorMessage = message
        switch session.phase {
        case .composing, .failed:
            session.phase = .failed(message)
        case .waiting, .streaming, .finished:
            break
        }
        onLayout()
    }

    func submitOrStop() {
        if session.showsStop {
            stop()
        } else {
            submit()
        }
    }

    func submit() {
        guard !session.showsStop else { return }
        if captureArmed {
            onCaptureScreen()
            return
        }
        beginSend(jpeg: nil, name: "")
    }

    func beginSend(jpeg: Data?, name: String, highlightFrame: CGRect? = nil) {
        let prompt = SystemPrompt.composed(
            override: store.sendEndpoint(hasImage: jpeg != nil || session.chips.contains { chip in
                if case .jpeg = chip.payload { return true }
                return false
            })?.systemPrompt ?? "",
            global: store.defaultSystemPrompt,
            preset: session.preset,
            now: Date()
        )
        let outcome = session.send(attachedJPEG: jpeg, attachmentName: name, systemPrompt: prompt)
        guard case .request(let messages) = outcome else {
            onLayout()
            return
        }
        if CaptureHighlight.shouldFlashOnSend(hasJPEG: jpeg != nil) {
            CaptureHighlight.flash(
                frame: highlightFrame,
                cornerRadius: IntelligenceGlowPolicy.cornerRadius(isHUD: false),
                context: .capture,
                space: .captureQuartz
            )
        }
        switch store.route(for: messages) {
        case .blocked(let message):
            lipDismissed = false
            session.fail(message)
            onLayout()
        case .cloud(let target):
            switch target {
            case .blocked(let message):
                lipDismissed = false
                session.fail(message)
                onLayout()
            case .ready(let url, let model, let key, let kind):
                captureArmed = false
                stickToBottom = true
                onSendBegan()
                startStream(url: url, model: model, apiKey: key, kind: kind, messages: messages)
                onLayout()
                focusField()
            }
        case .onDevice:
            captureArmed = false
            stickToBottom = true
            onSendBegan()
            startOnDeviceStream(messages: messages)
            onLayout()
            focusField()
        }
    }

    func stop() {
        applySession { $0.stop() }
        if session.phase == .finished {
            persistHistoryIfNeeded()
        }
        task?.cancel()
        task = nil
        onLayout()
    }

    func cancelForQuit() {
        task?.cancel()
        task = nil
    }

    @discardableResult
    func dismiss(clickOutside: Bool) -> Bool {
        let snapshot = session
        let excluded = historyExcluded
        let hide = session.dismiss(clickOutside: clickOutside)
        if hide {
            store.historyStore.record(
                session: snapshot,
                excludeFromHistory: excluded,
                historyEnabled: store.savesHistory,
                saveScreenshots: store.savesHistoryScreenshots
            )
            historyExpanded = false
            historyExcluded = false
            screenNotice = nil
            voiceStatus = nil
            lipDismissed = false
            captureArmed = false
            dictating = false
            task?.cancel()
            task = nil
        }
        onLayout()
        return hide
    }

    func persistHistoryIfNeeded() {
        store.historyStore.record(
            session: session,
            excludeFromHistory: historyExcluded,
            historyEnabled: store.savesHistory,
            saveScreenshots: store.savesHistoryScreenshots
        )
    }

    func toggleHistoryExclusion() {
        historyExcluded.toggle()
        onLayout()
    }

    func dismissLip() {
        var state = HUDErrorLip.State(
            phase: session.phase,
            errorMessage: session.errorMessage,
            screenNotice: screenNotice,
            voiceStatus: voiceStatus,
            dismissed: lipDismissed
        )
        HUDErrorLip.dismiss(&state, blockingMessage: store.blockingMessage)
        lipDismissed = state.dismissed
        session.phase = state.phase
        session.errorMessage = state.errorMessage
        screenNotice = state.screenNotice
        voiceStatus = state.voiceStatus
        onLayout()
    }

    func openSettings() {
        onOpenSettings()
    }

    func selectChat(providerID: UUID, modelID: String) {
        let pick = HUDModelMenu.picking(
            providerID: providerID,
            modelID: modelID,
            in: ChatModelSelection(
                chatID: store.defaultEndpointID,
                chatModelID: store.chatModelID,
                visionID: store.visionEndpointID,
                visionModelID: store.visionModelID
            ),
            secret: store.apiKey(for: providerID)
        )
        store.selectChat(
            providerID: pick.selection.chatID ?? providerID,
            modelID: pick.selection.chatModelID
        )
        onLayout()
    }

    func addContext() {
        onAddContext()
    }

    func toggleCapture() {
        captureArmed.toggle()
        screenNotice = nil
        onLayout()
    }

    func toggleDictation() {
        onToggleDictation()
        onLayout()
    }

    func setCaptureTarget(_ target: CaptureTarget) {
        store.captureTarget = target
    }

    func openScreenSettings() {
        guard let url = PrivacyPromptURL.screenRecording else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = PrivacyPromptURL.accessibility else { return }
        NSWorkspace.shared.open(url)
    }

    func openVoiceSettings() {
        guard let status = voiceStatus,
              let url = VoiceStatusCopy.systemSettingsURL(for: status)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Settings General: force the mic/speech system prompts or open Privacy panes.
    func promptVoicePrivacyFromSettings() {
        Task { @MainActor in
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch VoicePermission.settingsDecision(for: micStatus) {
            case .request:
                _ = await VoicePermission.requestMicrophone()
            case .openSettings:
                if let url = PrivacyPromptURL.microphone {
                    NSWorkspace.shared.open(url)
                }
            case .none, .requestAndOpenSettings:
                break
            }

            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            switch VoicePermission.settingsDecision(forSpeech: speechStatus) {
            case .request:
                _ = await VoicePermission.requestSpeech()
            case .openSettings:
                if let url = PrivacyPromptURL.speechRecognition {
                    NSWorkspace.shared.open(url)
                }
            case .none, .requestAndOpenSettings:
                break
            }

            voiceStatus = VoicePermission.deniedSentence()
        }
    }

    /// Settings General: force Screen Recording prompt and/or open its Privacy pane.
    func promptScreenPrivacyFromSettings() {
        switch ScreenGrab.settingsDecision(preflightGranted: CGPreflightScreenCaptureAccess()) {
        case .none:
            return
        case .request, .openSettings, .requestAndOpenSettings:
            _ = ScreenGrab.requestAccessFromSettings()
            openScreenSettings()
        }
    }

    /// Settings General: prompt Accessibility once when not trusted; open the pane as a fallback.
    func promptAccessibilityPrivacyFromSettings() {
        switch AccessibilityPermission.settingsDecision(trusted: AccessibilityPermission.isTrusted) {
        case .none:
            return
        case .request, .openSettings, .requestAndOpenSettings:
            let trusted = AccessibilityPermission.promptFromSettingsIfNeeded()
            if !trusted {
                openAccessibilitySettings()
            }
        }
    }

    func toggleHistory() {
        historyExpanded.toggle()
        onLayout()
    }

    func reportScreenFailure(_ error: ScreenGrabError) {
        screenNotice = SendFailureCopy.message(for: error)
        onLayout()
    }

    func focusField() {
        guard let promptEditor else { return }
        let view = promptEditor.promptFocusView
        view.window?.makeFirstResponder(view)
    }

    private func startOnDeviceStream(messages: [OutboundMessage]) {
        task?.cancel()
        clientSession = nil
        redirectGuard = nil
        consume(ignoreCancelledURLError: false, failureText: { _ in
            "The on-device model failed."
        }) {
            OnDeviceChat.stream(messages: messages)
        }
    }

    private func startStream(
        url: URL,
        model: String,
        apiKey: String,
        kind: CloudSendKind,
        messages: [OutboundMessage]
    ) {
        task?.cancel()
        let host = url.host ?? ""
        let (session, guardDelegate) = ChatClient.makeSession(
            host: host,
            requestTimeout: store.requestTimeoutSeconds
        )
        clientSession = session
        redirectGuard = guardDelegate
        let effort = store.reasoningEffort
        let request = ChatRequest(
            url: url,
            model: model,
            apiKey: apiKey,
            messages: messages,
            reasoningEffort: effort
        )
        consume(ignoreCancelledURLError: true, failureText: { error in
            SendFailureCopy.message(for: error)
        }) { [weak self] in
            switch kind {
            case .openaiCompletions:
                return ChatClient(session: session).stream(request)
            case .anthropicMessages:
                return AnthropicClient(session: session).stream(request)
            case .chatgptResponses:
                let credential = try await ChatGPTAuth.freshCredential(apiKey)
                let secret = ChatGPTAuth.serialize(credential)
                if let id = self?.store.endpoints.first(where: { self?.store.apiKey(for: $0.id) == apiKey })?.id {
                    self?.store.replaceChatSecret(secret, id: id)
                }
                return ChatGPTClient(session: session).stream(
                    ChatRequest(
                        url: url,
                        model: model,
                        apiKey: secret,
                        messages: messages,
                        reasoningEffort: effort
                    )
                )
            }
        }
    }

    private func consume(
        ignoreCancelledURLError: Bool,
        failureText: @escaping (Error) -> String,
        makeEvents: @escaping () async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
    ) {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let events = try await makeEvents()
                for try await event in events {
                    if Task.isCancelled { return }
                    switch event {
                    case .token(let token):
                        self.applySession { $0.receiveToken(token) }
                        self.onLayout()
                    case .done:
                        self.applySession { $0.finish() }
                        self.persistHistoryIfNeeded()
                        self.onLayout()
                        return
                    case .failure(let message):
                        self.lipDismissed = false
                        self.applySession { $0.fail(message) }
                        self.onLayout()
                        return
                    }
                }
                self.commitStreamIfNeeded()
            } catch is CancellationError {
                return
            } catch let error as URLError where ignoreCancelledURLError && error.code == .cancelled {
                return
            } catch {
                self.lipDismissed = false
                self.applySession { $0.fail(failureText(error)) }
                self.onLayout()
            }
        }
    }

    private func applySession(_ mutate: (inout Session) -> Void) {
        var next = session
        mutate(&next)
        session = next
    }

    /// If the stream ends without an explicit `.done` after tokens arrived, commit the live reply.
    private func commitStreamIfNeeded() {
        guard session.showsStop, !session.displayAnswer.isEmpty else { return }
        applySession { $0.finish() }
        persistHistoryIfNeeded()
        onLayout()
    }
}
