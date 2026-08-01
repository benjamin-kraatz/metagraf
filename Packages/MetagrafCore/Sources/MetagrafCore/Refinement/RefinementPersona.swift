import Foundation

/// A built-in perspective that guides terminology and voice during refinement.
public enum RefinementPersona: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case general
    case programmer
    case professionalWriter
    case novelAuthor
    case studentAcademic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "No persona"
        case .general: "General"
        case .programmer: "Programmer"
        case .professionalWriter: "Professional writer"
        case .novelAuthor: "Novel author"
        case .studentAcademic: "Student / academic"
        }
    }

    public var explanation: String {
        switch self {
        case .none: "Keep the selected formatting style’s existing behaviour."
        case .general: "Use clear, natural wording that fits a broad range of contexts."
        case .programmer: "Prefer correct technical terminology and concise engineering communication."
        case .professionalWriter: "Use polished, precise prose suited to professional and non-fiction writing."
        case .novelAuthor: "Use expressive, voice-aware narrative prose without inventing story details."
        case .studentAcademic: "Use clear, structured, academically appropriate wording."
        }
    }

    /// Trusted model guidance. These strings are never populated with user data.
    var instruction: String? {
        switch self {
        case .none:
            nil
        case .general:
            "Use clear, natural, broadly appropriate wording."
        case .programmer:
            "Prefer correct technical terminology and conventions, with concise engineering communication."
        case .professionalWriter:
            "Use polished, precise prose suited to professional and non-fiction writing."
        case .novelAuthor:
            "Use expressive, voice-aware narrative prose, but never invent facts, events, or story content."
        case .studentAcademic:
            "Use clear, structured, academically appropriate wording."
        }
    }
}

/// How strongly an active persona may reshape the speaker's wording.
public enum PersonaAdaptation: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimalCorrection
    case contextualPolish
    case strongAdaptation
    case prompting

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .minimalCorrection: "Minimal correction"
        case .contextualPolish: "Contextual polish"
        case .strongAdaptation: "Strong adaptation"
        case .prompting: "Prompting"
        }
    }

    public var explanation: String {
        switch self {
        case .minimalCorrection:
            "Only correct transcription, grammar, and domain terminology."
        case .contextualPolish:
            "Improve phrasing, terminology, and formatting while preserving meaning and certainty."
        case .strongAdaptation:
            "Rewrite more substantially for the persona while retaining the speaker’s meaning."
        case .prompting:
            "Turn terse dictation into a clear, context-rich prompt for an AI agent."
        }
    }

    /// Trusted model guidance. Only used when a persona is active.
    var instruction: String {
        switch self {
        case .minimalCorrection:
            "Only correct transcription errors, grammar, and domain-specific terminology; otherwise preserve the speaker's wording."
        case .contextualPolish:
            "Improve phrasing, terminology, and formatting, while preserving the speaker's meaning, facts, intent, and level of certainty."
        case .strongAdaptation:
            "You may rewrite substantially to suit the persona, while preserving the speaker's meaning, facts, intent, and level of certainty."
        case .prompting:
            "Transform the transcript into a clear, agent-ready prompt. Expand terse or fragmented requests with useful clarification while preserving the speaker's objective, facts, intent, uncertainty, and language."
        }
    }
}
