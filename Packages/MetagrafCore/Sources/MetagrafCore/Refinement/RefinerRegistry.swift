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
            guard await refiner.availability(for: context.locale).isAvailable else { continue }
            do {
                let refined = try await refiner.refine(corrected, context: context)
                let nonempty = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nonempty.isEmpty else {
                    logger.notice("\(refiner.identifier.rawValue, privacy: .public) returned empty text")
                    continue
                }
                return VocabularyRewriter.apply(nonempty, vocabulary: context.vocabulary)
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

    /// Loads the first suitable language model while speech is still being
    /// recorded. This is intentionally best-effort and never blocks dictation.
    public func prewarm(context: RefinementContext) async {
        guard context.usesLanguageModel, context.style.needsLanguageModel else { return }

        for refiner in modelRefiners {
            guard await refiner.availability(for: context.locale).isAvailable else { continue }
            await refiner.prewarm(context: context)
            return
        }
    }

    /// Availability of the first configured language model for a locale.
    public func languageModelAvailability(for locale: Locale) async -> RefinerAvailability {
        var lastReason: String?
        for refiner in modelRefiners {
            switch await refiner.availability(for: locale) {
            case .available:
                return .available
            case .unavailable(let reason):
                lastReason = reason
            }
        }
        return .unavailable(
            lastReason ?? String(localized: "No text model is configured.", bundle: .main)
        )
    }

    /// Why the language-model step is unavailable, for settings UI.
    public func languageModelUnavailableReason(for locale: Locale) async -> String? {
        switch await languageModelAvailability(for: locale) {
        case .available:
            nil
        case .unavailable(let reason):
            reason
        }
    }
}
