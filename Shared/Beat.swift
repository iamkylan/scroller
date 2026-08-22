import Foundation

/// One deliverable chunk of script — roughly a breath, roughly a sentence.
struct Beat: Identifiable, Sendable, Equatable {
    let id: Int
    /// What's shown and spoken, with any direction tags removed.
    let text: String
    /// Performance note pulled from `[square brackets]`, e.g. "warm, slower".
    let direction: String?
    /// Range into the script's flat token array, so the alignment engine can
    /// work on the whole script exactly as it does in Flow mode.
    let tokenRange: Range<Int>

    var wordCount: Int { tokenRange.count }
}

struct SegmentedScript: Sendable, Equatable {
    let beats: [Beat]
    let tokens: [String]

    static let empty = SegmentedScript(beats: [], tokens: [])
}
