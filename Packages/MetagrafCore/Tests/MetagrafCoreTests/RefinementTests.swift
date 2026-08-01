import Foundation
import Testing

@testable import MetagrafCore

@Suite("Rule-based refinement")
struct RuleBasedRefinerTests {
    private let refiner = RuleBasedRefiner()

    private func refine(
        _ text: String,
        style: RefinementStyle = .cleanup,
        vocabulary: [VocabularyEntry] = []
    ) async throws -> String {
        try await refiner.refine(
            text,
            context: RefinementContext(style: style, vocabulary: vocabulary)
        )
    }

    @Test("Raw style leaves the transcript completely alone")
    func rawIsUntouched() async throws {
        let spoken = "um so   i think ,  yeah"
        #expect(try await refine(spoken, style: .raw) == spoken)
    }

    @Test("Filler words are dropped")
    func stripsFillers() async throws {
        #expect(try await refine("um I think uh this works") == "I think this works")
    }

    @Test("Filler removal only matches whole words")
    func doesNotStripInsideWords() async throws {
        // "Umbrella" and "Uhura" start with filler spellings but are real words.
        #expect(try await refine("umbrella and uhura") == "Umbrella and uhura")
    }

    @Test("Spacing and stray punctuation gaps are tidied")
    func collapsesWhitespace() async throws {
        #expect(try await refine("hello    there , friend .") == "Hello there, friend.")
    }

    @Test("Sentences are capitalised")
    func capitalizesSentences() async throws {
        #expect(
            try await refine("this is one. this is two! and three?")
                == "This is one. This is two! And three?"
        )
    }

    @Test("Known mishearings are rewritten to the intended term")
    func appliesVocabulary() async throws {
        let vocabulary = [VocabularyEntry(term: "Metagraf", misheard: ["meta graph", "metagraph"])]
        #expect(
            try await refine("i opened meta graph today", vocabulary: vocabulary)
                == "I opened Metagraf today"
        )
    }

    @Test("Mishearing replacement respects word boundaries")
    func vocabularyRespectsWordBoundaries() async throws {
        let vocabulary = [VocabularyEntry(term: "Swift", misheard: ["swiff"])]
        #expect(
            try await refine("swiff and swiffer", vocabulary: vocabulary)
                == "Swift and swiffer"
        )
    }

    @Test("Regular expression characters in a term are treated literally")
    func vocabularyEscapesRegex() async throws {
        let vocabulary = [VocabularyEntry(term: "C++", misheard: ["c plus plus"])]
        #expect(
            try await refine("i write c plus plus", vocabulary: vocabulary)
                == "I write C++"
        )
    }

    @Test("Empty input stays empty")
    func handlesEmptyInput() async throws {
        #expect(try await refine("") == "")
    }
}

@Suite("Refinement styles")
struct RefinementStyleTests {
    @Test("Only the rewriting styles need a language model")
    func languageModelIsOnlyNeededForRewrites() {
        #expect(!RefinementStyle.raw.needsLanguageModel)
        #expect(!RefinementStyle.cleanup.needsLanguageModel)
        #expect(RefinementStyle.email.needsLanguageModel)
        #expect(RefinementStyle.message.needsLanguageModel)
        #expect(RefinementStyle.notes.needsLanguageModel)
    }

    @Test("A model reply wrapped in its own markers is unwrapped")
    func unwrapsMarkers() {
        let cleaned = AppleIntelligenceRefiner.cleanReply(
            "<transcript>\nHello there.\n</transcript>",
            original: "hello there"
        )
        #expect(cleaned == "Hello there.")
    }

    @Test("An empty model reply falls back to the original")
    func emptyReplyFallsBack() {
        #expect(AppleIntelligenceRefiner.cleanReply("   ", original: "hello") == "hello")
    }
}

@Suite("Refiner chain")
struct RefinerRegistryTests {
    /// Stands in for a language model, without needing one to be available.
    private struct StubRefiner: TextRefiner {
        let identifier = RefinerID(rawValue: "stub")
        var availability: RefinerAvailability
        var transform: @Sendable (String) throws -> String

        func refine(_ text: String, context: RefinementContext) async throws -> String {
            try transform(text)
        }
    }

    @Test("Raw style skips the whole chain")
    func rawSkipsEverything() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .available) { _ in "rewritten" }
        ])
        let result = await registry.refine("um hello", context: RefinementContext(style: .raw))
        #expect(result == "um hello")
    }

    @Test("Cleanup never reaches the language model")
    func cleanupStaysLocal() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .available) { _ in "should not be used" }
        ])
        let result = await registry.refine("um hello", context: RefinementContext(style: .cleanup))
        #expect(result == "Hello")
    }

    @Test("A rewriting style uses the language model")
    func rewritingUsesTheModel() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .available) { "[\($0)]" }
        ])
        let result = await registry.refine("um hello", context: RefinementContext(style: .email))
        #expect(result == "[Hello]")
    }

    @Test("An unavailable model leaves the cleaned-up text")
    func unavailableModelFallsBack() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .unavailable("nope")) { _ in "unused" }
        ])
        let result = await registry.refine("um hello", context: RefinementContext(style: .email))
        #expect(result == "Hello")
    }

    @Test("A failing model leaves the cleaned-up text rather than losing it")
    func failingModelFallsBack() async {
        struct Boom: Error {}
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .available) { _ in throw Boom() }
        ])
        let result = await registry.refine("um hello there", context: RefinementContext(style: .notes))
        #expect(result == "Hello there")
    }

    @Test("The first available model in the chain wins")
    func firstAvailableWins() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner(availability: .unavailable("off")) { _ in "first" },
            StubRefiner(availability: .available) { _ in "second" },
        ])
        let result = await registry.refine("hello", context: RefinementContext(style: .email))
        #expect(result == "second")
    }
}
