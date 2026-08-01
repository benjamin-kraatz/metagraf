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
    /// Infer the most useful format from the transcript and its destination.
    case intelligent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .raw: "Exactly as spoken"
        case .cleanup: "Clean up"
        case .email: "Email"
        case .message: "Message"
        case .notes: "Notes"
        case .intelligent: "Intelligent"
        }
    }

    public var explanation: String {
        switch self {
        case .raw: "Insert the transcript untouched."
        case .cleanup: "Drop “um” and “you know”, fix punctuation and capitalisation."
        case .email: "Tidy up and lay the text out as an email."
        case .message: "Keep it short and conversational."
        case .notes: "Condense into terse notes rather than full sentences."
        case .intelligent: "Adapt the wording and format to what you’re writing."
        }
    }

    /// Whether this style changes the text at all.
    public var isPassthrough: Bool { self == .raw }
    
    public var needsLanguageModel: Bool {
        switch self {
        case .raw: false
        case .cleanup, .email, .message, .notes, .intelligent: true
        }
    }
}

/// Information about where a transcript will be inserted.
///
/// `applicationName` is always safe to provide. The remaining fields are only
/// populated after the user opts in to nearby app context.
public struct RefinementDestinationContext: Sendable, Equatable {
    public var applicationName: String?
    public var windowTitle: String?
    public var focusedElementRole: String?
    public var focusedElementTitle: String?
    public var focusedElementDescription: String?
    public var placeholder: String?
    public var selectedText: String?
    public var nearbyText: String?

    public init(
        applicationName: String? = nil,
        windowTitle: String? = nil,
        focusedElementRole: String? = nil,
        focusedElementTitle: String? = nil,
        focusedElementDescription: String? = nil,
        placeholder: String? = nil,
        selectedText: String? = nil,
        nearbyText: String? = nil
    ) {
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.focusedElementRole = focusedElementRole
        self.focusedElementTitle = focusedElementTitle
        self.focusedElementDescription = focusedElementDescription
        self.placeholder = placeholder
        self.selectedText = selectedText
        self.nearbyText = nearbyText
    }

    public var hasRichContext: Bool {
        [
            windowTitle,
            focusedElementRole,
            focusedElementTitle,
            focusedElementDescription,
            placeholder,
            selectedText,
            nearbyText,
        ].contains { $0?.isEmpty == false }
    }
}

/// Applies the privacy and prompt-size limits to focused-field context.
public enum RefinementContextLimit {
    public static let maximumTextCharacters = 4_000
    public static let maximumMetadataCharacters = 256

    public static func bounded(
        applicationName: String?,
        windowTitle: String?,
        focusedElementRole: String?,
        focusedElementTitle: String?,
        focusedElementDescription: String?,
        placeholder: String?,
        selectedText: String?,
        nearbyText: String?,
        isSecure: Bool
    ) -> RefinementDestinationContext {
        let selected = isSecure ? nil : prefix(selectedText, maximumTextCharacters)
        let remaining = maximumTextCharacters - (selected?.count ?? 0)
        let nearby = isSecure ? nil : prefix(nearbyText, remaining)

        return RefinementDestinationContext(
            applicationName: prefix(applicationName, maximumMetadataCharacters),
            windowTitle: prefix(windowTitle, maximumMetadataCharacters),
            focusedElementRole: prefix(focusedElementRole, maximumMetadataCharacters),
            focusedElementTitle: prefix(focusedElementTitle, maximumMetadataCharacters),
            focusedElementDescription: prefix(focusedElementDescription, maximumMetadataCharacters),
            placeholder: prefix(placeholder, maximumMetadataCharacters),
            selectedText: selected,
            nearbyText: nearby
        )
    }

    /// A centered character range around the current selection or caret.
    public static func excerptRange(
        totalLength: Int,
        selection: NSRange,
        maximumLength: Int
    ) -> NSRange {
        guard totalLength > 0, maximumLength > 0 else { return NSRange(location: 0, length: 0) }

        let length = min(totalLength, maximumLength)
        let safeLocation = min(max(0, selection.location), totalLength)
        let safeSelectionLength = min(max(0, selection.length), totalLength - safeLocation)
        let center = safeLocation + safeSelectionLength / 2
        let start = min(max(0, center - length / 2), totalLength - length)
        return NSRange(location: start, length: length)
    }

    private static func prefix(_ value: String?, _ length: Int) -> String? {
        guard let value, !value.isEmpty, length > 0 else { return nil }
        return String(value.prefix(length))
    }
}

/// Everything a refiner needs to know about the text it is given.
public struct RefinementContext: Sendable {
    public var style: RefinementStyle
    public var persona: RefinementPersona
    public var personaAdaptation: PersonaAdaptation
    public var locale: Locale
    public var vocabulary: [VocabularyEntry]
    public var destination: RefinementDestinationContext

    /// Source-compatible alias for the destination application's display name.
    public var targetApplication: String? {
        get { destination.applicationName }
        set { destination.applicationName = newValue }
    }

    /// Whether a language model may be used. Turning this off keeps the original
    /// transcript rather than rewriting it.
    public var usesLanguageModel: Bool

    /// Whether persona adaptation should produce an agent-ready prompt instead
    /// of using the selected style's usual output format.
    public var isPrompting: Bool {
        Self.isPrompting(
            style: style,
            persona: persona,
            adaptation: personaAdaptation
        )
    }

    /// Shared rule for callers that need to decide whether to capture context
    /// before a complete refinement context has been assembled.
    public static func isPrompting(
        style: RefinementStyle,
        persona: RefinementPersona,
        adaptation: PersonaAdaptation
    ) -> Bool {
        style != .raw && persona != .none && adaptation == .prompting
    }

    public init(
        style: RefinementStyle,
        persona: RefinementPersona = .none,
        personaAdaptation: PersonaAdaptation = .contextualPolish,
        locale: Locale = .current,
        vocabulary: [VocabularyEntry] = [],
        targetApplication: String? = nil,
        usesLanguageModel: Bool = true,
        destination: RefinementDestinationContext? = nil
    ) {
        self.style = style
        self.persona = persona
        self.personaAdaptation = personaAdaptation
        self.locale = locale
        self.vocabulary = vocabulary
        var resolvedDestination = destination ?? RefinementDestinationContext()
        if resolvedDestination.applicationName == nil {
            resolvedDestination.applicationName = targetApplication
        }
        self.destination = resolvedDestination
        self.usesLanguageModel = usesLanguageModel
    }
}

/// What refinement produced, and which step produced it.
public struct RefinementOutcome: Sendable, Equatable {
    public var text: String
    public var refiner: RefinerID

    public init(text: String, refiner: RefinerID) {
        self.text = text
        self.refiner = refiner
    }
}

public struct RefinerID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

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
