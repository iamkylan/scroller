import AVFoundation
import Foundation
import NaturalLanguage
import Speech

/// Live on-device transcription built on iOS 26's SpeechAnalyzer. The older
/// SFSpeechRecognizer path is deliberately not used: it caps server recognition
/// at about a minute, which is useless for reading a script.
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
        guard case .idle = status else { return }
        status = .preparing
        finalizedWords = []
        volatileWords = []

        if let failure = await requestPermissions() {
            status = .failed(failure)
            return
        }

        guard let locale = await Self.resolveLocale(for: scriptBody) else {
            status = .failed(.noSupportedLocale)
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
            try await prepareModel(for: transcriber, locale: locale)
        } catch {
            status = .failed(.modelUnavailable(error.localizedDescription))
            return
        }

        do {
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
        } catch {
            status = .failed(.other(error.localizedDescription))
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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Captured as locals so the audio thread never touches actor state.
        let targetFormat = analyzerFormat
        let converter: AVAudioConverter? = {
            guard let targetFormat, targetFormat != inputFormat else { return nil }
            return AVAudioConverter(from: inputFormat, to: targetFormat)
        }()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converter, let targetFormat else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            guard let converted = Self.convert(buffer, using: converter, to: targetFormat) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

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
