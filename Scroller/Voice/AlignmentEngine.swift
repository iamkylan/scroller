import Foundation

/// Finds where in the script the speaker currently is.
///
/// The naive approach — search the transcript for the last recognized word —
/// fails immediately, because scripts repeat phrases and you teleport to the
/// wrong paragraph. Instead this searches only a window around the current
/// position, and aligns a short tail of recognized words against it with a
/// gap-tolerant DP so skipped words, ad-libs and filler don't break the lock.
struct AlignmentEngine {
    struct Match: Equatable {
        /// Index of the next script token the speaker has not reached yet.
        let tokenIndex: Int
        let confidence: Double
    }

    /// How far behind and ahead of the cursor to look. Keeping this tight is
    /// what stops a repeated phrase later in the script from stealing the lock.
    var lookBehind = 14
    var lookAhead = 48
    /// Recognized words considered per attempt. Too few and common words match
    /// anywhere; too many and a long ad-lib drags the score down.
    var spokenTail = 8
    /// Below this, a single common word ("the") would match anywhere in the
    /// window with perfect confidence and yank the cursor around.
    var minimumSpokenWords = 3

    private let exactScore = 2.0
    private let fuzzyScore = 0.75
    private let mismatchScore = -1.5
    private let gapScore = -1.0

    func match(spoken: [String], scriptTokens: [String], cursor: Int) -> Match? {
        let recent = Array(spoken.suffix(spokenTail))
        guard recent.count >= minimumSpokenWords, !scriptTokens.isEmpty else { return nil }

        let windowStart = max(0, cursor - lookBehind)
        let windowEnd = min(scriptTokens.count, cursor + lookAhead)
        guard windowStart < windowEnd else { return nil }
        let window = Array(scriptTokens[windowStart..<windowEnd])

        // Semi-global alignment: the spoken tail must be fully consumed, but it
        // may start and end anywhere inside the window for free.
        let rows = recent.count
        let columns = window.count
        var previous = [Double](repeating: 0, count: columns + 1)
        var current = [Double](repeating: 0, count: columns + 1)

        for row in 1...rows {
            current[0] = previous[0] + gapScore
            for column in 1...columns {
                let diagonal = previous[column - 1] + similarity(recent[row - 1], window[column - 1])
                let skipSpoken = previous[column] + gapScore
                let skipScript = current[column - 1] + gapScore
                current[column] = max(diagonal, max(skipSpoken, skipScript))
            }
            swap(&previous, &current)
        }

        // `previous` holds the final row after the last swap.
        var bestColumn = 0
        var bestScore = -Double.infinity
        for column in 0...columns where previous[column] > bestScore {
            bestScore = previous[column]
            bestColumn = column
        }

        // A short tail is inherently weaker evidence than a long one, even
        // when every word in it matched.
        let evidence = min(1, Double(rows) / 5)
        let confidence = bestScore / (Double(rows) * exactScore) * evidence
        guard confidence > 0 else { return nil }
        return Match(tokenIndex: windowStart + bestColumn, confidence: min(confidence, 1))
    }

    private func similarity(_ spoken: String, _ script: String) -> Double {
        if spoken == script { return exactScore }
        // Recognizer near-misses ("furniture" / "furnitures") should still count.
        guard abs(spoken.count - script.count) <= 3 else { return mismatchScore }
        let distance = editDistance(Array(spoken), Array(script))
        let ratio = 1 - Double(distance) / Double(max(spoken.count, script.count))
        return ratio >= 0.75 ? fuzzyScore : mismatchScore
    }

    private func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(substitution, min(previous[j] + 1, current[j - 1] + 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
