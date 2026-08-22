import Foundation

/// Wraps the Line-mode state machine with live transcription.
@MainActor
@Observable
final class BeatTracker {
    private(set) var status: SpeechTranscription.Status = .idle
    private(set) var progress = BeatProgress(script: .empty)
    private(set) var lastMatchAt: Date?

    private let transcription = SpeechTranscription()

    var currentBeat: Beat? { progress.currentBeat }
    var previousBeat: Beat? { progress.previousBeat }
    var nextBeat: Beat? { progress.nextBeat }
    var takeCount: Int { progress.takeCount }
    var beatCount: Int { progress.script.beats.count }
    var index: Int { progress.index }

    var isDelivering: Bool {
        guard let lastMatchAt else { return false }
        return Date.now.timeIntervalSince(lastMatchAt) < 1.5
    }

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
        await transcription.stop()
        status = transcription.status
    }

    func advance() { progress.advance() }
    func goBack() { progress.goBack() }
}
