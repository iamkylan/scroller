import AVFoundation
import Foundation
import NaturalLanguage
import Speech

/// Live on-device transcription built on iOS 26's SpeechAnalyzer. The older
/// SFSpeechRecognizer path is deliberately not used: it caps server recognition
/// at about a minute, which is useless for reading a script.
enum AudioSetupError: LocalizedError {
    case inputUnavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "The microphone isn't available right now."
        case .unsupportedFormat: "This device's microphone format can't be read."
        }
    }
}

@MainActor
@Observable
final class SpeechTranscription {
    enum Failure: Equatable {
        case microphoneDenied
        case speechDenied
        case noSupportedLocale
        case modelUnavailable(String)
        case other(String)

        /// Permission problems need the user to go and fix something. Model
        /// problems don't, so the prompter can quietly keep scrolling instead
        /// of stranding someone mid-take.
        var allowsConstantSpeedFallback: Bool {
            switch self {
            case .microphoneDenied, .speechDenied: false
            case .noSupportedLocale, .modelUnavailable, .other: true
            }
        }
    }

    enum Status: Equatable {
        case idle
        case preparing
        case installingModel(Double)
        case listening
        case failed(Failure)
    }

    private(set) var status: Status = .idle
    private(set) var locale: Locale?

    /// Fires with the running list of normalized words heard this session.
    var onWords: (([String]) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var audioEngine: AVAudioEngine?
    private var resultsTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    private var finalizedWords: [String] = []
    private var volatileWords: [String] = []

    /// Only the tail is ever used for matching, so the history is bounded.
    private let retainedWordCount = 240

    var isRunning: Bool { audioEngine?.isRunning == true }

    // MARK: - Lifecycle

    func start(scriptBody: String, vocabulary: [String]) async {
        // A previous failure must not wedge this shut: toggling voice off and
        // on again is the obvious way to retry.
        if case .failed = status { status = .idle }
        guard case .idle = status else { return }
        status = .preparing
        finalizedWords = []
        volatileWords = []

        VoiceDiagnostics.begin(.permissions)
        if let failure = await requestPermissions() {
            status = .failed(failure)
            VoiceDiagnostics.finish()
            return
        }

        VoiceDiagnostics.begin(.locale)
        guard let locale = await Self.resolveLocale(for: scriptBody) else {
            status = .failed(.noSupportedLocale)
            VoiceDiagnostics.finish()
            return
        }
        self.locale = locale

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // Volatile results are what make this feel live — waiting for
            // finalized text would put the scroll a sentence behind the voice.
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        do {
            VoiceDiagnostics.begin(.model)
            try await prepareModel(for: transcriber, locale: locale)
        } catch {
            status = .failed(.modelUnavailable(error.localizedDescription))
            VoiceDiagnostics.finish()
            return
        }

        do {
            VoiceDiagnostics.begin(.analyzer)
            let context = AnalysisContext()
            // Telling the recognizer what is about to be said is a large
            // accuracy win when the words are known in advance.
            context.contextualStrings = [.general: vocabulary]

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.setContext(context)
            self.analyzer = analyzer

            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation

            try await analyzer.start(inputSequence: stream)
            try startAudio(convertingTo: format, into: continuation)

            observeResults(from: transcriber)
            status = .listening
            VoiceDiagnostics.finish()
        } catch {
            status = .failed(.other(error.localizedDescription))
            VoiceDiagnostics.finish()
            await stop()
        }
    }

    func stop() async {
        resultsTask?.cancel()
        resultsTask = nil
        progressTask?.cancel()
        progressTask = nil

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        await analyzer?.cancelAndFinishNow()
        analyzer = nil

        if let locale { _ = await AssetInventory.release(reservedLocale: locale) }
        transcriber = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .failed = status {} else { status = .idle }
    }

    // MARK: - Audio

    private func startAudio(
        convertingTo analyzerFormat: AVAudioFormat?,
        into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        VoiceDiagnostics.begin(.audioSession)
        let session = AVAudioSession.sharedInstance()
        // No options: duckOthers is rejected outright by .record, and Bluetooth
        // input cannot be enabled for it either. Passing either one makes
        // setCategory throw and voice tracking never starts.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Reading inputNode with no input route raises rather than throwing.
        guard session.isInputAvailable else { throw AudioSetupError.inputUnavailable }

        VoiceDiagnostics.begin(.audioEngine)
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // installTap raises an Objective-C exception on a zero-rate or
        // zero-channel format, which no Swift catch can stop. That happens when
        // the mic is held by something else or the route isn't ready yet, so it
        // has to be checked rather than caught.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioSetupError.inputUnavailable
        }

        // Captured as locals so the audio thread never touches actor state.
        let targetFormat = analyzerFormat
        var converter: AVAudioConverter?
        if let targetFormat, targetFormat != inputFormat {
            guard let made = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                // Sending unconverted buffers would be silently wrong rather
                // than loudly broken, so fail instead.
                throw AudioSetupError.unsupportedFormat
            }
            converter = made
        }
        let resolvedConverter = converter

        VoiceDiagnostics.begin(.tap)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let resolvedConverter, let targetFormat else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            guard let converted = Self.convert(buffer, using: resolvedConverter, to: targetFormat) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        VoiceDiagnostics.begin(.engineStart)
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 128
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let outcome = converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard outcome != .error, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Results

    private func observeResults(from transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    let text = String(result.text.characters)
                    self?.ingest(text: text, isFinal: result.isFinal)
                }
            } catch {
                self?.status = .failed(.other(error.localizedDescription))
            }
        }
    }

    private func ingest(text: String, isFinal: Bool) {
        let heard = ScriptTokenizer.spokenWords(in: text)
        guard !heard.isEmpty else { return }

        if isFinal {
            finalizedWords.append(contentsOf: heard)
            if finalizedWords.count > retainedWordCount {
                finalizedWords.removeFirst(finalizedWords.count - retainedWordCount)
            }
            volatileWords = []
        } else {
            volatileWords = heard
        }

        onWords?(finalizedWords + volatileWords)
    }

    // MARK: - Setup helpers

    private func prepareModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)

        let installed = await SpeechTranscriber.installedLocales
        let target = locale.identifier(.bcp47)
        if installed.contains(where: { $0.identifier(.bcp47) == target }) { return }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        status = .installingModel(0)

        let progress = request.progress
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.status = .installingModel(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { progressTask?.cancel(); progressTask = nil }

        try await request.downloadAndInstall()
    }

    private func requestPermissions() async -> Failure? {
        guard await AVAudioApplication.requestRecordPermission() else { return .microphoneDenied }
        return await Self.speechAuthorization() == .authorized ? nil : .speechDenied
    }

    /// Deliberately nonisolated: SFSpeechRecognizer calls its completion on a
    /// background queue, and a main-actor-isolated closure traps there.
    nonisolated private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Picks the recognition language from the script itself, so a French
    /// voice-over works on an English phone without a setting to remember.
    private static func resolveLocale(for text: String) async -> Locale? {
        var candidates: [Locale] = []

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let dominant = recognizer.dominantLanguage {
            candidates.append(Locale(identifier: dominant.rawValue))
        }
        candidates.append(.current)
        candidates.append(Locale(identifier: "en-US"))

        for candidate in candidates {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return supported
            }
        }
        return await SpeechTranscriber.supportedLocales.first
    }
}
