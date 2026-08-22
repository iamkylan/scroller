import Foundation
import NaturalLanguage

/// Splits a script into beats you can actually perform one at a time.
enum BeatSegmenter {
    /// A beat shorter than this gets absorbed into the next one — "Right." is
    /// not a take on its own.
    static let minimumWords = 4
    /// Beyond this a beat stops being one breath, so it's split at punctuation.
    static let maximumWords = 24

    static func segment(_ body: String) -> SegmentedScript {
        var beats: [Beat] = []
        var tokens: [String] = []

        for chunk in chunks(in: body) {
            let beatTokens = ScriptTokenizer.tokens(in: chunk.text).map(\.text)
            guard !beatTokens.isEmpty else { continue }
            let start = tokens.count
            tokens.append(contentsOf: beatTokens)
            beats.append(
                Beat(
                    id: beats.count,
                    text: chunk.text,
                    direction: chunk.direction,
                    tokenRange: start..<tokens.count
                )
            )
        }

        return SegmentedScript(beats: beats, tokens: tokens)
    }

    // MARK: - Chunking

    private struct Chunk {
        var text: String
        var direction: String?
    }

    private static func chunks(in body: String) -> [Chunk] {
        var result: [Chunk] = []
        // A direction on its own line applies to whatever comes next.
        var pendingDirection: String?

        for paragraph in paragraphs(in: body) {
            let (stripped, direction) = extractDirection(from: paragraph)

            guard !stripped.isEmpty else {
                // Nothing but a direction tag — carry it to the next beat.
                if let direction {
                    pendingDirection = [pendingDirection, direction].compactMap { $0 }.joined(separator: ", ")
                }
                continue
            }

            var carried = [pendingDirection, direction].compactMap { $0 }.joined(separator: ", ")
            pendingDirection = nil

            for sentence in split(sentences(in: stripped)) {
                result.append(Chunk(text: sentence, direction: carried.isEmpty ? nil : carried))
                // The direction belongs to the first beat it introduces.
                carried = ""
            }
        }

        return result
    }

    private static func paragraphs(in body: String) -> [String] {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func extractDirection(from paragraph: String) -> (String, String?) {
        var notes: [String] = []
        var stripped = paragraph

        while let range = stripped.firstRange(of: /\[([^\]]{1,80})\]/) {
            let inner = stripped[range].dropFirst().dropLast()
            notes.append(String(inner).trimmingCharacters(in: .whitespaces))
            stripped.replaceSubrange(range, with: " ")
        }

        let cleaned = stripped
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, notes.isEmpty ? nil : notes.joined(separator: ", "))
    }

    private static func sentences(in paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph

        var pieces: [String] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let sentence = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { pieces.append(sentence) }
            return true
        }
        return pieces.isEmpty ? [paragraph] : pieces
    }

    /// Merges the too-short and divides the too-long.
    private static func split(_ sentences: [String]) -> [String] {
        var merged: [String] = []
        for sentence in sentences {
            if let last = merged.last, wordCount(last) < minimumWords {
                merged[merged.count - 1] = last + " " + sentence
            } else {
                merged.append(sentence)
            }
        }
        // A trailing fragment has nothing after it, so it goes backwards instead.
        if merged.count > 1, let last = merged.last, wordCount(last) < minimumWords {
            merged.removeLast()
            merged[merged.count - 1] += " " + last
        }

        return merged.flatMap(divide)
    }

    private static func divide(_ sentence: String) -> [String] {
        guard wordCount(sentence) > maximumWords else { return [sentence] }

        // Only ever split at punctuation. A split mid-clause reads worse than
        // a beat that runs slightly long.
        let characters = Array(sentence)
        let middle = characters.count / 2
        let breakPoints = characters.indices.filter { index in
            characters[index] == "," || characters[index] == ";" || characters[index] == "\u{2014}"
        }
        guard let best = breakPoints.min(by: { abs($0 - middle) < abs($1 - middle) }) else {
            return [sentence]
        }

        let head = String(characters[..<best]).trimmingCharacters(in: .whitespaces)
        let tail = String(characters[(best + 1)...]).trimmingCharacters(in: .whitespaces)
        guard wordCount(head) >= minimumWords, wordCount(tail) >= minimumWords else { return [sentence] }
        return divide(head) + divide(tail)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
