import AppKit

extension HUDController {
    func setWake(_ on: Bool) {
        if on {
            Task { await startWakeCapture(prompt: true) }
            return
        }
        store.wakeOnAxiom = false
        if !model.dictating {
            stopCapture()
        }
    }

    func toggleDictation() {
        guard PromptInFlightPolicy.isEditable(phase: model.session.phase) else { return }
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

    func startWakeCapture(prompt: Bool) async {
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

    func startDictationCapture() async {
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

    func requestVoicePermission() async -> Bool {
        model.voicePermissionPrompt = true
        defer { model.voicePermissionPrompt = false }
        let mic = await VoicePermission.requestMicrophone()
        let speech = await VoicePermission.requestSpeech()
        return mic && speech
    }

    func beginCapture() {
        if model.debugDriven { return }
        if let capture, capture.isRunning { return }
        capture?.stop()
        let session = VoiceCapture()
        session.onTranscript = { [weak self] text, isFinal in
            self?.handleTranscript(text, isFinal: isFinal)
        }
        session.onFailure = { [weak self] message in
            self?.handleCaptureFailure(message)
        }
        capture = session
        session.start()
    }

    func stopCapture() {
        capture?.stop()
        capture = nil
    }

    func handleCaptureFailure(_ message: String) {
        if model.debugDriven { return }
        if model.dictating || model.voicePermissionPrompt {
            model.voiceStatus = message
        }
        setDictating(false)
        stopCapture()
    }

    func handleTranscript(_ text: String, isFinal: Bool) {
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

    func applyDictation(_ recognized: String, isFinal: Bool) {
        guard PromptInFlightPolicy.isEditable(phase: model.session.phase) else { return }
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

    func handleSendBegan() {
        endDictation(keepWakeCapture: true)
    }

    func setDictating(_ on: Bool) {
        model.dictating = on
        if !on {
            dictationBase = ""
            silentSince = nil
        }
        model.onLayout()
        syncDictationGlow()
    }

    func endDictation(keepWakeCapture: Bool) {
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

    func startVoicePolling() {
        voicePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.pollVoice()
            }
        }
    }

    func pollVoice() {
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
}
