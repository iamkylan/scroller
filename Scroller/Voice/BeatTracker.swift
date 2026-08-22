import Foundation

/// Wraps the Line-mode state machine with live transcription.
@MainActor
@Observable
final class BeatTracker {
    private(set) var status: SpeechTranscription.Status = .idle
    private(set) var progress = BeatProgress(script: .empty)
    private(set) var lastMatchAt: Date?
    /// Held as state rather than derived from a timestamp: a computed
    /// "was I speaking recently" never tells SwiftUI when it stops being true.
    private(set) var isSpeaking = false

    private let transcription = SpeechTranscription()
    private var speechTimeout: Task<Void, Never>?

    var currentBeat: Beat? { progress.currentBeat }
    var previousBeat: Beat? { progress.previousBeat }
    var nextBeat: Beat? { progress.nextBeat }
    var takeCount: Int { progress.takeCount }
    var beatCount: Int { progress.script.beats.count }
    var beats: [Beat] { progress.script.beats }
    var index: Int { progress.index }

    var isUsingFallback: Bool {
        guard case .failed(let failure) = status else { return false }
        return failure.allowsConstantSpeedFallback
    }

    func load(_ script: Script) {
        progress = BeatProgress(script: BeatSegmenter.segment(script.body))
        lastMatchAt = nil
    }

    func startListening(script: Script) async {
        transcription.onWords = { [weak self] words in
            guard let self else { return }
            if self.progress.ingest(words) { self.lastMatchAt = .now }
            self.status = self.transcription.status
            self.noteSpeech()
        }
        await transcription.start(
            scriptBody: script.body,
            vocabulary: ScriptTokenizer.contextualVocabulary(
                from: ScriptTokenizer.tokens(in: script.body)
            )
        )
        status = transcription.status
    }

    func stopListening() async {
        speechTimeout?.cancel()
        speechTimeout = nil
        isSpeaking = false
        await transcription.stop()
        status = transcription.status
    }

    /// Marks speech as live and schedules it to lapse, so the interface can get
    /// out of the way mid-take and come back once you've stopped.
    private func noteSpeech() {
        isSpeaking = true
        speechTimeout?.cancel()
        speechTimeout = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            self?.isSpeaking = false
        }
    }

    func advance() { progress.advance() }
    func goBack() { progress.goBack() }
}
