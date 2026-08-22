import Foundation

/// A spoken-word position in the script, carrying the UTF-16 offset the text
/// view needs to turn it back into a screen position.
struct ScriptToken: Sendable, Equatable {
    let text: String
    let characterIndex: Int
}

enum ScriptTokenizer {
    /// Splits the script into comparable words. Digits are deliberately left as
    /// digits rather than spelled out, because the transcriber also emits them
    /// as digits — spelling them out would create a mismatch, not fix one.
    static func tokens(in body: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        var current = ""
        var currentStart = 0
        var offset = 0

        func flush() {
            if !current.isEmpty, let normalized = normalize(current) {
                tokens.append(ScriptToken(text: normalized, characterIndex: currentStart))
            }
            current = ""
        }

        for character in body {
            if character.isLetter || character.isNumber || character == "'" || character == "\u{2019}" {
                if current.isEmpty { currentStart = offset }
                current.append(character)
            } else {
                flush()
            }
            offset += character.utf16.count
        }
        flush()
        return tokens
    }

    /// Lowercased, diacritic-folded, apostrophes removed — so "Déjà" and "deja"
    /// compare equal, and "don't" survives the transcriber writing "dont".
    static func normalize(_ word: String) -> String? {
        let folded = word
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        return folded.isEmpty ? nil : folded
    }

    static func spokenWords(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "\u{2019}" })
            .compactMap { normalize(String($0)) }
    }

    /// Distinctive vocabulary handed to the recognizer as context. Knowing what
    /// is about to be said is a large accuracy win for a prompter.
    static func contextualVocabulary(from tokens: [ScriptToken], limit: Int = 120) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens where token.text.count >= 5 {
            guard seen.insert(token.text).inserted else { continue }
            result.append(token.text)
            if result.count == limit { break }
        }
        return result
    }
}
