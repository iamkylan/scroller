import Foundation

/// Turns arbitrary shared text into a script. Shared by the share extension,
/// the paste button, and the Shortcuts action so all three behave identically.
enum ScriptImport {
    static func makeScript(from rawText: String, title: String? = nil) -> Script? {
        let body = clean(rawText)
        guard !body.isEmpty else { return nil }
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Script(
            title: resolvedTitle?.isEmpty == false ? resolvedTitle! : Script.inferredTitle(from: body),
            body: body
        )
    }

    /// LLM output arrives full of markdown scaffolding that reads terribly out
    /// loud, so it's stripped on the way in rather than left for you to delete
    /// by hand before a shoot.
    private static func clean(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)

            // Heading markers, blockquotes, list bullets.
            line = line.replacing(/^\s{0,3}#{1,6}\s+/, with: "")
            line = line.replacing(/^\s{0,3}>\s?/, with: "")
            line = line.replacing(/^\s{0,3}[-*+]\s+/, with: "")

            // Horizontal rules carry no spoken content.
            if line.wholeMatch(of: /\s*([-*_])\s*(\1\s*){2,}/) != nil { line = "" }

            // Emphasis, inline code, and links, keeping the words inside.
            line = line.replacing(/\[([^\]]+)\]\([^)]*\)/) { $0.output.1 }
            // The marker has to hug its content, otherwise arithmetic like
            // "3 * 4 * 5" reads as emphasis and loses the operators.
            line = line.replacing(/\*\*([^\s*][^*\n]*?[^\s*]|[^\s*])\*\*/) { $0.output.1 }
            line = line.replacing(/\*([^\s*][^*\n]*?[^\s*]|[^\s*])\*/) { $0.output.1 }
            line = line.replacing(/`([^`\n]+)`/) { $0.output.1 }

            lines.append(line.trimmingCharacters(in: .whitespaces))
        }

        // Collapse runs of blank lines down to a single paragraph break.
        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty && collapsed.last?.isEmpty == true { continue }
            collapsed.append(line)
        }

        return collapsed
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
