import Foundation

enum ReadingTime {
    private static func seconds(words: Int, wordsPerMinute: Double) -> Int {
        Int((Double(words) / max(wordsPerMinute, 1) * 60).rounded())
    }

    /// "48s" / "2m 05s" — for the library list.
    static func spelled(words: Int, wordsPerMinute: Double) -> String {
        let total = seconds(words: words, wordsPerMinute: wordsPerMinute)
        guard total >= 60 else { return "\(total)s" }
        return "\(total / 60)m " + String(format: "%02ds", total % 60)
    }

    /// "0:48" — for the prompter readout.
    static func clock(words: Int, wordsPerMinute: Double) -> String {
        let total = seconds(words: words, wordsPerMinute: wordsPerMinute)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
