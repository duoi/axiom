import AppKit
import Observation

@MainActor
@Observable
final class HUDModel {
    var session = Session()
    var stickToBottom = true
    weak var textField: NSTextField?

    let store: EndpointStore
    var onOpenSettings: () -> Void = {}
    var onAddContext: () -> Void = {}
    var onCaptureScreen: () -> Void = {}
    var onLayout: () -> Void = {}
    var historyExpanded = false
    var screenNotice: String?
    var captureArmed = false
    var cardIsKey = true
    var reduceTransparency = false
    var dictating = false
    var voiceStatus: String?
    var voicePermissionPrompt = false
    var onToggleDictation: () -> Void = {}
    var onSetWake: (Bool) -> Void = { _ in }
    var onSendBegan: () -> Void = {}
    var debugDriven = false

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

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            session: session,
            captureArmed: captureArmed,
            dictating: dictating,
            voiceStatus: voiceStatus,
            screenNotice: screenNotice
        )
    }

    func apply(_ snapshot: DebugSnapshot) {
        debugDriven = true
        cancelForQuit()
        session = snapshot.session
        captureArmed = snapshot.captureArmed
        dictating = snapshot.dictating
        voiceStatus = snapshot.voiceStatus
        screenNotice = snapshot.screenNotice
        pushDraftToField(session.draft)
        onLayout()
    }

    func setDraft(_ text: String) {
        session.draft = text
        pushDraftToField(text)
        onLayout()
    }

    func pushDraftToField(_ text: String) {
        guard let textField else { return }
        if textField.stringValue != text {
            textField.stringValue = text
        }
        guard let editor = textField.currentEditor() else { return }
        if editor.string != text {
            editor.string = text
            let end = (text as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
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

    func beginSend(jpeg: Data?, name: String) {
        let outcome = session.send(attachedJPEG: jpeg, attachmentName: name)
        guard case .request(let messages) = outcome else {
            onLayout()
            return
        }
        switch store.route(for: messages) {
        case .blocked(let message):
            session.fail(message)
            onLayout()
        case .cloud(let target):
            switch target {
            case .blocked(let message):
                session.fail(message)
                onLayout()
            case .ready(let url, let model, let key):
                captureArmed = false
                stickToBottom = true
                onSendBegan()
                startStream(url: url, model: model, apiKey: key, messages: messages)
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
        session.stop()
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
        let hide = session.dismiss(clickOutside: clickOutside)
        if hide {
            historyExpanded = false
            screenNotice = nil
            captureArmed = false
            dictating = false
            task?.cancel()
            task = nil
        }
        onLayout()
        return hide
    }

    func openSettings() {
        onOpenSettings()
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func toggleHistory() {
        historyExpanded.toggle()
        onLayout()
    }

    func reportScreenFailure(permission: Bool) {
        screenNotice = permission
            ? "Allow Screen Recording in System Settings"
            : "The screen capture failed."
        onLayout()
    }

    func focusField() {
        guard let textField, let window = textField.window else { return }
        window.makeFirstResponder(textField)
    }

    private func startOnDeviceStream(messages: [OutboundMessage]) {
        task?.cancel()
        clientSession = nil
        redirectGuard = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in OnDeviceChat.stream(messages: messages) {
                    if Task.isCancelled { return }
                    switch event {
                    case .token(let token):
                        self.session.receiveToken(token)
                        self.onLayout()
                    case .done:
                        self.session.finish()
                        self.onLayout()
                        return
                    case .failure(let message):
                        self.session.fail(message)
                        self.onLayout()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.session.fail("The on-device model failed.")
                self.onLayout()
            }
        }
    }

    private func startStream(url: URL, model: String, apiKey: String, messages: [OutboundMessage]) {
        task?.cancel()
        let host = url.host ?? ""
        let (session, guardDelegate) = ChatClient.makeSession(host: host)
        clientSession = session
        redirectGuard = guardDelegate
        let client = ChatClient(session: session)
        let request = ChatRequest(
            url: url,
            model: model,
            apiKey: apiKey,
            messages: messages
        )
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in client.stream(request) {
                    if Task.isCancelled { return }
                    switch event {
                    case .token(let token):
                        self.session.receiveToken(token)
                        self.onLayout()
                    case .done:
                        self.session.finish()
                        self.onLayout()
                        return
                    case .failure(let message):
                        self.session.fail(message)
                        self.onLayout()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as URLError where error.code == .timedOut {
                self.session.fail("The request timed out.")
                self.onLayout()
            } catch {
                self.session.fail("The request failed.")
                self.onLayout()
            }
        }
    }
}
