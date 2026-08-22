import Foundation

struct Script: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var updatedAt: Date = .now

    var wordCount: Int { Script.wordCount(of: body) }

    var preview: String {
        body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Uses the first non-empty line as the title, which is almost always what
    /// an LLM or Notes export gives us anyway.
    static func inferredTitle(from body: String) -> String {
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstLine.isEmpty else { return "Untitled script" }
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }
}
