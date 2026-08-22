import Foundation

/// The Line-mode state machine, kept free of audio and actors so its behaviour
/// can be exercised directly: feed it words, assert where it lands.
struct BeatProgress {
    private(set) var index = 0
    private(set) var takesByBeat: [Int: Int] = [:]

    let script: SegmentedScript

    private var engine = AlignmentEngine()
    private var hasReachedBeatEnd = false
    /// How much speech had been heard when the current take finished. New words
    /// beyond this that still match the beat mean another take has begun —
    /// which is more reliable than watching for the matcher to travel back to
    /// the top of the line, since a whole repeat can arrive in one update.
    private var wordsHeardAtTakeEnd = 0
    /// Enough new speech to be a genuine restart rather than the recognizer
    /// revising the tail of what it already reported.
    private let restartWordThreshold = 3

    private let acceptThreshold = 0.40
    /// Promotion needs firmer evidence than staying put: a wrong promotion
    /// interrupts a take, while a missed one costs a tap.
    private let promoteThreshold = 0.55
    /// Words into the next beat that count as having moved on. Two is enough to
    /// be deliberate without making you read half the line before it advances.
    private let promotionWords = 2

    init(script: SegmentedScript) {
        self.script = script
    }

    var currentBeat: Beat? { beat(at: index) }
    var previousBeat: Beat? { beat(at: index - 1) }
    var nextBeat: Beat? { beat(at: index + 1) }
    var takeCount: Int { takesByBeat[index] ?? 0 }

    private func beat(at index: Int) -> Beat? {
        script.beats.indices.contains(index) ? script.beats[index] : nil
    }

    mutating func advance() {
        guard index + 1 < script.beats.count else { return }
        index += 1
        hasReachedBeatEnd = false
        wordsHeardAtTakeEnd = 0
    }

    mutating func goBack() {
        guard index > 0 else { return }
        index -= 1
        hasReachedBeatEnd = false
        wordsHeardAtTakeEnd = 0
    }

    /// Returns true when the words moved or changed something, so the caller
    /// knows there was a live match rather than silence.
    @discardableResult
    mutating func ingest(_ words: [String]) -> Bool {
        guard let current = currentBeat else { return false }

        // The window is this beat plus the next: everything the speaker could
        // plausibly be saying right now, and nothing else. Repeating a line
        // therefore needs no special handling — it's just a backward move
        // inside a small window.
        let upperBound = nextBeat?.tokenRange.upperBound ?? current.tokenRange.upperBound
        let window = current.tokenRange.lowerBound..<upperBound
        guard let match = engine.match(spoken: words, scriptTokens: script.tokens, window: window) else {
            return false
        }

        if let next = nextBeat,
           match.tokenIndex >= next.tokenRange.lowerBound + promotionWords,
           match.confidence >= promoteThreshold {
            index += 1
            hasReachedBeatEnd = false
            wordsHeardAtTakeEnd = 0
            return true
        }

        guard match.confidence >= acceptThreshold else { return false }

        if hasReachedBeatEnd, words.count >= wordsHeardAtTakeEnd + restartWordThreshold {
            // More was said after the take finished, and it still matches this
            // beat, so it's being delivered again.
            hasReachedBeatEnd = false
        }

        if match.tokenIndex >= current.tokenRange.upperBound - 2 {
            // Delivered through to the end of the line — that's a take.
            if !hasReachedBeatEnd {
                takesByBeat[index, default: 0] += 1
                hasReachedBeatEnd = true
                wordsHeardAtTakeEnd = words.count
            }
        } else if match.tokenIndex <= current.tokenRange.lowerBound + 2 {
            hasReachedBeatEnd = false
        }
        return true
    }
}
