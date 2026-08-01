import Foundation

/// A word Metagraf should get right.
///
/// Names, product names, and jargon are what dictation gets wrong most often,
/// and they are exactly the words a user cannot shrug off.
public struct VocabularyEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID

    /// The correct spelling. Fed to the engine to bias recognition toward it.
    public var term: String

    /// What the engine tends to hear instead. Used to rewrite the transcript
    /// when biasing alone was not enough.
    public var misheard: [String]

    public init(id: UUID = UUID(), term: String, misheard: [String] = []) {
        self.id = id
        self.term = term
        self.misheard = misheard
    }
}

/// An app-specific override, so dictating into a terminal can behave
/// differently from dictating into a mail composer.
public struct AppRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID

    public var bundleIdentifier: String
    public var displayName: String

    /// Overrides the global insertion strategy when this app is frontmost.
    public var insertion: InsertionStrategy?

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        insertion: InsertionStrategy? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.insertion = insertion
    }
}
