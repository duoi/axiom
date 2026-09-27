import AVFoundation
import Foundation
import Speech

enum VoiceAssetStatus: Equatable, Sendable {
    case installed
    case downloading
    case missing
    case unsupported

    var statusSentence: String {
        switch self {
        case .installed:
            return ""
        case .downloading:
            return VoiceStatusCopy.downloading
        case .missing:
            return VoiceStatusCopy.missingModel
        case .unsupported:
            return VoiceStatusCopy.unsupportedModel
        }
    }
}

enum VoicePermission {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var speechGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var isGranted: Bool {
        microphoneGranted && speechGranted
    }

    static func deniedSentence() -> String? {
        if !microphoneGranted { return VoiceStatusCopy.micDenied }
        if !speechGranted { return VoiceStatusCopy.speechDenied }
        return nil
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}

@MainActor
final class VoiceCapture {
    var onTranscript: (String, Bool) -> Void = { _, _ in }
    var onSpeechDetected: (Bool) -> Void = { _ in }
    var onFailure: (String) -> Void = { _ in }

    private var analyzer: SpeechAnalyzer?
    private var retainedInput: AnyObject?
    private var sessionRunner: SessionRunner?
    private var reservedLocale: Locale?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var runTask: Task<Void, Never>?
    private var reportedFailure = false

    var isRunning: Bool { runTask != nil }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    static func makeModules() async -> [any SpeechModule] {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? .current
        return [makeTranscriber(locale: locale)]
    }

    static func assetStatus(for modules: [any SpeechModule]? = nil) async -> VoiceAssetStatus {
        let resolved = if let modules {
            modules
        } else {
            await makeModules()
        }
        switch await AssetInventory.status(forModules: resolved) {
        case .installed:
            return .installed
        case .downloading:
            return .downloading
        case .supported:
            return .missing
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    static func ensureInstalled(_ requested: [any SpeechModule]? = nil) async -> VoiceAssetStatus {
        let modules: [any SpeechModule]
        if let requested {
            modules = requested
        } else {
            modules = await makeModules()
        }
        var status = await AssetInventory.status(forModules: modules)
        if status == .installed {
            return .installed
        }
        if status == .supported || status == .downloading {
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: modules) {
                try? await request.downloadAndInstall()
            }
            status = await AssetInventory.status(forModules: modules)
        }
        switch status {
        case .installed:
            return .installed
        case .downloading:
            return .downloading
        case .supported:
            return .missing
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    func start() {
        guard runTask == nil else { return }
        reportedFailure = false
        runTask = Task { [weak self] in
            await self?.runPipeline()
        }
    }

    func transcribe(file url: URL) {
        guard runTask == nil else { return }
        reportedFailure = false
        runTask = Task { [weak self] in
            await self?.runFile(url)
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        teardownInput()
        let analyzer = self.analyzer
        self.analyzer = nil
        let locale = reservedLocale
        reservedLocale = nil
        Task {
            await analyzer?.cancelAndFinishNow()
            if let locale {
                _ = await AssetInventory.release(reservedLocale: locale)
            }
        }
    }

    private func teardownInput() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        sessionRunner?.stop()
        sessionRunner = nil
        retainedInput = nil
    }

    private func runPipeline() async {
        if let denied = VoicePermission.deniedSentence() {
            fail(denied)
            return
        }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? .current
        if (try? await AssetInventory.reserve(locale: locale)) == true {
            reservedLocale = locale
        }
        let transcriber = Self.makeTranscriber(locale: locale)
        let modules: [any SpeechModule] = [transcriber]
        let asset = await Self.ensureInstalled(modules)
        guard asset == .installed else {
            fail(asset.statusSentence)
            return
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        if let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) {
            try? await analyzer.prepareToAnalyze(in: format)
        }

        let textTask = Self.collectTranscripts(transcriber) { [weak self] text, isFinal in
            self?.onTranscript(text, isFinal)
        } onFailure: { [weak self] in
            self?.fail(VoiceStatusCopy.captureFailed)
        }

        do {
            try await startInput(analyzer: analyzer, modules: modules)
        } catch is CancellationError {
            // Stop requested.
        } catch {
            fail(VoiceStatusCopy.captureFailed)
        }
        textTask.cancel()
        _ = await textTask.result
        if runTask != nil {
            runTask = nil
        }
    }

    private func startInput(analyzer: SpeechAnalyzer, modules: [any SpeechModule]) async throws {
        if #available(macOS 27.0, *) {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                throw VoiceCaptureError.noDevice
            }
            let provider = try await CaptureInputSequenceProvider.providerWithSession(
                from: device,
                compatibleWith: modules
            )
            retainedInput = provider
            let runner = SessionRunner(provider.captureSession)
            sessionRunner = runner
            let running = await Task.detached { runner.start() }.value
            guard running else {
                throw VoiceCaptureError.sessionIdle
            }
            _ = try await analyzer.analyzeSequence(provider.analyzerInputs)
            return
        }
        try await startEngine(analyzer: analyzer)
    }

    private func runFile(_ url: URL) async {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? .current
        let transcriber = Self.makeTranscriber(locale: locale)
        let modules: [any SpeechModule] = [transcriber]
        let asset = await Self.ensureInstalled(modules)
        guard asset == .installed else {
            fail(asset.statusSentence)
            return
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        let textTask = Self.collectTranscripts(transcriber) { [weak self] text, isFinal in
            self?.onTranscript(text, isFinal)
        } onFailure: { [weak self] in
            self?.fail(VoiceStatusCopy.captureFailed)
        }
        do {
            let file = try AVAudioFile(forReading: url)
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch is CancellationError {
            // Stop requested.
        } catch {
            fail(VoiceStatusCopy.captureFailed)
        }
        let drained = await Self.waitForResults(textTask, seconds: 5)
        if !drained {
            textTask.cancel()
        }
        _ = await textTask.result
        if runTask != nil {
            runTask = nil
        }
    }

    private func startEngine(analyzer: SpeechAnalyzer) async throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: Self.int16Copy(buffer)))
        }
        self.engine = engine
        inputContinuation = continuation
        engine.prepare()
        try engine.start()
        _ = try await analyzer.analyzeSequence(stream)
    }

    private static func collectTranscripts(
        _ transcriber: SpeechTranscriber,
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            do {
                for try await result in transcriber.results {
                    if Task.isCancelled { return }
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await onTranscript(text, isFinal)
                }
            } catch is CancellationError {
                return
            } catch {
                await onFailure()
            }
        }
    }

    private static func waitForResults(_ task: Task<Void, Never>, seconds: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let finished = await group.next() ?? false
            group.cancelAll()
            return finished
        }
    }

    private func fail(_ message: String) {
        guard !reportedFailure else { return }
        reportedFailure = true
        onFailure(message.isEmpty ? VoiceStatusCopy.captureFailed : message)
        stop()
    }

    private static func copyPCM(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return buffer
        }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        }
        return copy
    }

    private static func int16Copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if buffer.format.commonFormat == .pcmFormatInt16 {
            return copyPCM(buffer)
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ), let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else {
            return copyPCM(buffer)
        }
        output.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let source = buffer.floatChannelData, let destination = output.int16ChannelData else {
            return copyPCM(buffer)
        }
        for channel in 0..<channels {
            for frame in 0..<frames {
                let sample = max(-1, min(1, source[channel][frame]))
                destination[channel][frame] = Int16(sample * 32767)
            }
        }
        return output
    }
}

private final class SessionRunner: @unchecked Sendable {
    private let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }

    func start() -> Bool {
        if !session.isRunning {
            session.startRunning()
        }
        return session.isRunning
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

private enum VoiceCaptureError: Error {
    case noDevice
    case sessionIdle
}
