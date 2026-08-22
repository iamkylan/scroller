import Foundation

/// Turns recognized speech into a position in the script.
@MainActor
@Observable
final class VoiceTracker {
    private(set) var status: SpeechTranscription.Status = .idle
    /// UTF-16 offset of the next word the speaker has not reached yet.
    private(set) var characterIndex: Int?
    private(set) var confidence: Double = 0
    private(set) var lastMatchAt: Date?
    private(set) var lastSpeechAt: Date?

    /// Fires when the tracked position moves, so the prompter can recompute
    /// where that word sits on screen rather than doing it every frame.
    var onPositionChanged: (() -> Void)?

    private let transcription = SpeechTranscription()
    private var engine = AlignmentEngine()
    private var tokens: [ScriptToken] = []
    private var tokenTexts: [String] = []
    private var cursor = 0

    /// Genuine reading scores well clear of this; off-script speech lands near
    /// zero, so the gap is wide enough to be a hard cutoff.
    private let acceptThreshold = 0.40
    /// Moving backwards is how a restart-after-flub recovers, but it needs
    /// stronger evidence than moving forwards.
    private let rewindThreshold = 0.70
    /// A big forward jump is more likely a mis-lock than genuinely skipping
    /// half a page, so it has to be well evidenced too.
    private let longJumpTokens = 30
    private let longJumpThreshold = 0.65

    var isLocked: Bool {
        guard let lastMatchAt else { return false }
        return Date.now.timeIntervalSince(lastMatchAt) < 2.5
    }

    /// True when speech is being heard but none of it matches the script —
    /// you're ad-libbing, and the text should keep drifting rather than freeze.
    var isOffScript: Bool {
        guard let lastSpeechAt, Date.now.timeIntervalSince(lastSpeechAt) < 2 else { return false }
        guard let lastMatchAt else { return true }
        return Date.now.timeIntervalSince(lastMatchAt) > 3
    }

    func start(script: Script) async {
        tokens = ScriptTokenizer.tokens(in: script.body)
        tokenTexts = tokens.map(\.text)
        cursor = 0
        characterIndex = nil
        confidence = 0
        lastMatchAt = nil
        lastSpeechAt = nil

        transcription.onWords = { [weak self] words in
            self?.consume(words)
        }

        await transcription.start(
            scriptBody: script.body,
            vocabulary: ScriptTokenizer.contextualVocabulary(from: tokens)
        )
        status = transcription.status
    }

    func stop() async {
        await transcription.stop()
        status = transcription.status
    }

    /// Reset to the top without tearing down the audio session.
    func rewindToStart() {
        cursor = 0
        characterIndex = nil
        confidence = 0
        lastMatchAt = nil
        onPositionChanged?()
    }

    private func consume(_ words: [String]) {
        status = transcription.status
        lastSpeechAt = .now

        guard let match = engine.match(spoken: words, scriptTokens: tokenTexts, cursor: cursor) else { return }

        let advance = match.tokenIndex - cursor
        let required: Double = if advance < 0 {
            rewindThreshold
        } else if advance > longJumpTokens {
            longJumpThreshold
        } else {
            acceptThreshold
        }
        guard match.confidence >= required else { return }

        cursor = match.tokenIndex
        confidence = match.confidence
        lastMatchAt = .now

        // The cursor is the next unspoken token; scrolling it to the reading
        // line puts the words you are about to say under the marker.
        let clamped = min(cursor, tokens.count - 1)
        characterIndex = clamped >= 0 ? tokens[clamped].characterIndex : nil
        onPositionChanged?()
    }
}
