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
    var onLayout: () -> Void = {}

    private var task: Task<Void, Never>?
    private var clientSession: URLSession?
    private var redirectGuard: RedirectGuard?

    init(store: EndpointStore) {
        self.store = store
    }

    func setDraft(_ text: String) {
        session.draft = text
        onLayout()
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
        if store.blockingMessage != nil {
            onLayout()
            return
        }
        guard case .success(let url) = store.resolvedURL else {
            onLayout()
            return
        }
        let outcome = session.send()
        guard case .request(let messages) = outcome else {
            onLayout()
            return
        }
        stickToBottom = true
        startStream(url: url, messages: messages)
        onLayout()
        focusField()
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

    func focusField() {
        guard let textField, let window = textField.window else { return }
        window.makeFirstResponder(textField)
    }

    private func startStream(url: URL, messages: [OutboundMessage]) {
        task?.cancel()
        let host = url.host ?? ""
        let (session, guardDelegate) = ChatClient.makeSession(host: host)
        clientSession = session
        redirectGuard = guardDelegate
        let client = ChatClient(session: session)
        let request = ChatRequest(
            url: url,
            model: store.model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: store.apiKey,
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
