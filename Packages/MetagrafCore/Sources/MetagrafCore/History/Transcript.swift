import Foundation
import SwiftData

/// One completed dictation.
@Model
public final class Transcript {
    public var createdAt: Date
    public var text: String

    /// What the engine produced before any cleanup, kept so a bad refinement
    /// can be compared against the original rather than silently replacing it.
    public var rawText: String

    public var localeIdentifier: String
    public var engineIdentifier: String
    public var durationSeconds: Double
    public var wordCount: Int

    /// Where the text was headed.
    public var appBundleIdentifier: String?
    public var appName: String?

    public init(
        createdAt: Date = .now,
        text: String,
        rawText: String? = nil,
        localeIdentifier: String,
        engineIdentifier: String,
        durationSeconds: Double,
        appBundleIdentifier: String? = nil,
        appName: String? = nil
    ) {
        self.createdAt = createdAt
        self.text = text
        self.rawText = rawText ?? text
        self.localeIdentifier = localeIdentifier
        self.engineIdentifier = engineIdentifier
        self.durationSeconds = durationSeconds
        self.wordCount = text.split(whereSeparator: \.isWhitespace).count
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
    }

    /// Speaking rate for this dictation, in words per minute.
    public var wordsPerMinute: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(wordCount) / durationSeconds) * 60)
    }
}
