import Foundation

/// Replaces known mishearings with their preferred vocabulary terms.
///
/// Runs without Apple Intelligence so corrections still apply for “Exactly as
/// spoken” and when the language model is unavailable. Matching is
/// case-insensitive and respects word boundaries, including multi-word phrases.
public enum VocabularyRewriter {
    public static func apply(_ text: String, vocabulary: [VocabularyEntry]) -> String {
        guard !text.isEmpty else { return text }

        let replacements = vocabulary.flatMap { entry -> [(pattern: String, term: String)] in
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return [] }
            return entry.misheard.compactMap { misheard in
                let pattern = misheard.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pattern.isEmpty else { return nil }
                guard pattern.caseInsensitiveCompare(term) != .orderedSame else { return nil }
                return (pattern, term)
            }
        }

        guard !replacements.isEmpty else { return text }

        // Longer phrases first so “meta graph” wins over “meta”.
        let ordered = replacements.sorted { $0.pattern.count > $1.pattern.count }

        var result = text
        for replacement in ordered {
            result = replaceOccurrences(of: replacement.pattern, with: replacement.term, in: result)
        }
        return result
    }

    private static func replaceOccurrences(of pattern: String, with term: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(
                pattern: #"\b\#(escaped)\b"#,
                options: [.caseInsensitive]
            )
        } catch {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: term)
        )
    }
}
