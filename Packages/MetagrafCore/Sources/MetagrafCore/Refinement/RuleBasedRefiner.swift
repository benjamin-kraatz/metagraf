import Foundation

/// Deterministic cleanup that always runs, before any language model sees the
/// text.
///
/// It costs nothing and never changes meaning, which makes it the right floor:
/// even when Apple Intelligence is unavailable or too slow, dictation still
/// produces text that reads properly.
public struct RuleBasedRefiner: TextRefiner, Sendable {
    public let identifier = RefinerID.rules

    public var availability: RefinerAvailability { .available }

    /// Words people say while thinking, which they never mean to write down.
    /// Only stripped when they stand alone, so "um" inside a word is safe.
    static let fillers: Set<String> = [
        "um", "uh", "erm", "hmm", "mhm",
        "äh", "ähm", "öh",
    ]

    public init() {}

    public func refine(_ text: String, context: RefinementContext) async throws -> String {
        guard context.style != .raw else { return text }

        var result = applyVocabulary(to: text, entries: context.vocabulary)
        result = removeFillers(from: result)
        result = collapseWhitespace(in: result)
        result = capitalizeSentences(in: result)
        return result
    }

    // MARK: - Steps

    /// Rewrites known mishearings to the term the user actually meant.
    func applyVocabulary(to text: String, entries: [VocabularyEntry]) -> String {
        var result = text

        for entry in entries where !entry.term.isEmpty {
            for misheard in entry.misheard where !misheard.isEmpty {
                result = result.replacingOccurrences(
                    of: "\\b\(NSRegularExpression.escapedPattern(for: misheard))\\b",
                    with: entry.term,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        return result
    }

    func removeFillers(from text: String) -> String {
        let kept = text.split(separator: " ", omittingEmptySubsequences: false).filter { word in
            let bare = word
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            return !Self.fillers.contains(bare)
        }
        return kept.joined(separator: " ")
    }

    func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            // Dictation often leaves a space before punctuation.
            .replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capitalises the first letter of the text and of each new sentence.
    func capitalizeSentences(in text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: character.uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalizeNext = true
                }
            }
        }

        return result
    }
}
