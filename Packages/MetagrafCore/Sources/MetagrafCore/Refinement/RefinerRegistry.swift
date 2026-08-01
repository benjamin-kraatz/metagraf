import Foundation
import OSLog

/// Runs the refinement chain: deterministic cleanup first, then a language
/// model if the chosen style needs one and a model is available.
///
/// Every step can fail without consequence — the text from the previous step is
/// carried forward — so a transcript always reaches the user.
public struct RefinerRegistry: Sendable {
    private let rules: RuleBasedRefiner
    private let modelRefiners: [any TextRefiner]
    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Refinement")

    /// `modelRefiners` are tried in order; the first available one is used.
    /// Additional backends plug in here without changes elsewhere.
    public init(
        rules: RuleBasedRefiner = RuleBasedRefiner(),
        modelRefiners: [any TextRefiner] = [AppleIntelligenceRefiner()]
    ) {
        self.rules = rules
        self.modelRefiners = modelRefiners
    }

    public func refine(_ text: String, context: RefinementContext) async -> String {
        guard context.style != .raw else { return text }

        let cleaned = (try? await rules.refine(text, context: context)) ?? text
        guard context.style.needsLanguageModel else { return cleaned }

        for refiner in modelRefiners {
            guard await refiner.availability.isAvailable else { continue }
            do {
                return try await refiner.refine(cleaned, context: context)
            } catch {
                logger.notice(
                    """
                    \(refiner.identifier.rawValue, privacy: .public) declined: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }

        return cleaned
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
