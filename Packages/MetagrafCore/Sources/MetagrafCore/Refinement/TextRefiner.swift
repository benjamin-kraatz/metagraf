import Foundation

/// How a transcript should be tidied before it is inserted.
public enum RefinementStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Insert exactly what was heard.
    case raw
    /// Remove filler words and fix punctuation, without changing the wording.
    case cleanup
    /// Slightly more formal, laid out as an email would be.
    case email
    /// Short and casual.
    case message
    /// Terse, as notes rather than prose.
    case notes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .raw: "Exactly as spoken"
        case .cleanup: "Clean up"
        case .email: "Email"
        case .message: "Message"
        case .notes: "Notes"
        }
    }

    public var explanation: String {
        switch self {
        case .raw: "Insert the transcript untouched."
        case .cleanup: "Drop “um” and “you know”, fix punctuation and capitalisation."
        case .email: "Tidy up and lay the text out as an email."
        case .message: "Keep it short and conversational."
        case .notes: "Condense into terse notes rather than full sentences."
        }
    }

    /// Whether a language model is needed, or the rule-based pass suffices.
    public var needsLanguageModel: Bool {
        switch self {
        case .raw, .cleanup: false
        case .email, .message, .notes: true
        }
    }
}

/// Everything a refiner needs to know about the text it is given.
public struct RefinementContext: Sendable {
    public var style: RefinementStyle
    public var locale: Locale
    public var vocabulary: [VocabularyEntry]

    /// Name of the app the text is headed for, when known.
    public var targetApplication: String?

    public init(
        style: RefinementStyle,
        locale: Locale = .current,
        vocabulary: [VocabularyEntry] = [],
        targetApplication: String? = nil
    ) {
        self.style = style
        self.locale = locale
        self.vocabulary = vocabulary
        self.targetApplication = targetApplication
    }
}

public struct RefinerID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let rules = RefinerID(rawValue: "rules")
    public static let appleIntelligence = RefinerID(rawValue: "apple.intelligence")
}

public enum RefinerAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool { self == .available }
}

/// Tidies a raw transcript.
///
/// The protocol exists so other backends — a local or hosted language model —
/// can be added later without touching the dictation pipeline.
public protocol TextRefiner: Sendable {
    var identifier: RefinerID { get }
    var availability: RefinerAvailability { get async }
    func refine(_ text: String, context: RefinementContext) async throws -> String
}
