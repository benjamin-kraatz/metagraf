import Foundation
import Testing

@testable import MetagrafCore

@Suite("Vocabulary rewriter")
struct VocabularyRewriterTests {
    @Test("Misheard phrases are rewritten to their preferred term")
    func rewritesMisheardPhrases() {
        let vocabulary = [
            VocabularyEntry(term: "Metagraf", misheard: ["meta graph", "metagraph"]),
        ]
        let result = VocabularyRewriter.apply(
            "I opened meta graph and then metagraph again.",
            vocabulary: vocabulary
        )
        #expect(result == "I opened Metagraf and then Metagraf again.")
    }

    @Test("Matching is case-insensitive and preserves the preferred spelling")
    func caseInsensitive() {
        let vocabulary = [VocabularyEntry(term: "Kubernetes", misheard: ["kube netes"])]
        let result = VocabularyRewriter.apply("try KUBE NETES next", vocabulary: vocabulary)
        #expect(result == "try Kubernetes next")
    }

    @Test("Partial word matches are left alone")
    func respectsWordBoundaries() {
        let vocabulary = [VocabularyEntry(term: "AI", misheard: ["a"])]
        let result = VocabularyRewriter.apply("a plan for apples", vocabulary: vocabulary)
        #expect(result == "AI plan for apples")
    }

    @Test("Longer mishearings win over shorter ones")
    func longerMatchesFirst() {
        let vocabulary = [
            VocabularyEntry(term: "Metagraf", misheard: ["meta", "meta graph"]),
        ]
        let result = VocabularyRewriter.apply("open meta graph please", vocabulary: vocabulary)
        #expect(result == "open Metagraf please")
    }

    @Test("Empty vocabulary leaves the transcript unchanged")
    func emptyVocabularyIsNoOp() {
        #expect(VocabularyRewriter.apply("hello", vocabulary: []) == "hello")
        #expect(
            VocabularyRewriter.apply(
                "hello",
                vocabulary: [VocabularyEntry(term: "Metagraf")]
            ) == "hello"
        )
    }

    @Test("Blank terms and blank mishearings are ignored")
    func blanksAreIgnored() {
        let vocabulary = [
            VocabularyEntry(term: "  ", misheard: ["meta graph"]),
            VocabularyEntry(term: "Metagraf", misheard: ["", "  "]),
        ]
        #expect(VocabularyRewriter.apply("meta graph", vocabulary: vocabulary) == "meta graph")
    }
}

@Suite("Vocabulary through the refiner chain")
struct VocabularyRefinerPipelineTests {
    private struct StubRefiner: TextRefiner {
        let identifier = RefinerID(rawValue: "stub")
        var availability: RefinerAvailability = .available
        var transform: @Sendable (String) throws -> String

        func refine(_ text: String, context: RefinementContext) async throws -> String {
            try transform(text)
        }
    }

    @Test("Raw style still applies vocabulary rewrites")
    func rawStillRewritesVocabulary() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner { _ in "should not run" }
        ])
        let result = await registry.refine(
            "open meta graph",
            context: RefinementContext(
                style: .raw,
                vocabulary: [VocabularyEntry(term: "Metagraf", misheard: ["meta graph"])]
            )
        )
        #expect(result == "open Metagraf")
    }

    @Test("Language-model output is rewritten again after refinement")
    func rewriteAfterModel() async {
        let registry = RefinerRegistry(modelRefiners: [
            StubRefiner { _ in "cleaned meta graph" }
        ])
        let result = await registry.refine(
            "um meta graph",
            context: RefinementContext(
                style: .cleanup,
                vocabulary: [VocabularyEntry(term: "Metagraf", misheard: ["meta graph"])]
            )
        )
        #expect(result == "cleaned Metagraf")
    }
}
