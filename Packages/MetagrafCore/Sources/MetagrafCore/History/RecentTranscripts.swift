import Foundation
import OSLog

/// One entry in the shared list of things recently dictated.
public struct RecentTranscript: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// A short list of recent transcripts, shared with the keyboard extension.
///
/// Deliberately not SwiftData. The keyboard only ever needs the last handful of
/// entries, and a keyboard extension runs under a hard memory limit where
/// standing up a persistent store to read twenty strings is a poor trade. The
/// full history stays in the app's SwiftData store; this is the slice the
/// extension can afford.
@MainActor
public final class RecentTranscripts {
    public static let shared = RecentTranscripts()

    /// Enough to find what you just said, few enough to stay cheap to load.
    public static let limit = 20

    private static let key = "recent.transcripts"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Recents")

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Metagraf.appGroupIdentifier)
            ?? .standard
    }

    /// Newest first.
    public func all() -> [RecentTranscript] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        do {
            return try JSONDecoder().decode([RecentTranscript].self, from: data)
        } catch {
            logger.error("Could not read recent transcripts: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var entries = all()
        // Saying the same thing twice should move it up, not fill the list.
        entries.removeAll { $0.text == trimmed }
        entries.insert(RecentTranscript(text: trimmed), at: 0)
        write(Array(entries.prefix(Self.limit)))
    }

    public func remove(_ entry: RecentTranscript) {
        write(all().filter { $0.id != entry.id })
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func write(_ entries: [RecentTranscript]) {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: Self.key)
        } catch {
            logger.error("Could not save recent transcripts: \(error.localizedDescription, privacy: .public)")
        }
    }
}
