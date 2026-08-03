import Foundation
import OSLog

/// Runs a language-model refinement when the chosen style needs one and a model
/// is available.
///
/// Every step can fail without consequence — the text from the previous step is
/// preserved — so a transcript always reaches the user.
public struct RefinerRegistry: Sendable {
    private let modelRefiners: [any TextRefiner]
    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Refinement")

    /// `modelRefiners` are tried in order; the first available one is used.
    /// Additional backends plug in here without changes elsewhere.
    public init(
        modelRefiners: [any TextRefiner] = [AppleIntelligenceRefiner()]
    ) {
        self.modelRefiners = modelRefiners
    }

    public func refine(_ text: String, context: RefinementContext) async -> String {
        // Vocabulary corrections are deterministic and cheap; apply them even
        // when the user chose “Exactly as spoken” or the language model is off.
        let corrected = VocabularyRewriter.apply(text, vocabulary: context.vocabulary)

        guard context.style != .raw else { return corrected }
        guard context.usesLanguageModel, context.style.needsLanguageModel else { return corrected }

        for refiner in modelRefiners {
            guard await refiner.availability.isAvailable else { continue }
            do {
                let refined = try await refiner.refine(corrected, context: context)
                return VocabularyRewriter.apply(refined, vocabulary: context.vocabulary)
            } catch {
                logger.notice(
                    """
                    \(refiner.identifier.rawValue, privacy: .public) declined: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }

        return corrected
    }

    /// Why the language-model step is unavailable, for the settings UI to show.
    public func languageModelUnavailableReason() async -> String? {
        for refiner in modelRefiners {
            switch await refiner.availability {
            case .available: return nil
            case .unavailable(let reason): return reason
            }
        }
        return String(localized: "No text model is configured.", bundle: .main)
    }
}
