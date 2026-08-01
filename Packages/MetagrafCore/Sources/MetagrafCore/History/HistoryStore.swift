import Foundation
import OSLog
import SwiftData

/// Stores completed dictations, subject to the user's retention setting.
///
/// A dictation app sees everything its user writes, so "keep nothing" is a
/// first-class option rather than an afterthought, and old entries are pruned
/// without being asked.
@MainActor
public final class HistoryStore {
    public let container: ModelContainer

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "History")

    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(
            "Metagraf",
            schema: Schema([Transcript.self]),
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(
            for: Transcript.self,
            configurations: configuration
        )
    }

    private var context: ModelContext { container.mainContext }

    /// Records a dictation, unless the user has asked for nothing to be kept.
    public func record(_ transcript: Transcript, retentionDays: Int) {
        guard retentionDays > 0 else { return }

        context.insert(transcript)
        save()
        prune(retentionDays: retentionDays)
    }

    /// Deletes entries older than the retention window.
    public func prune(retentionDays: Int) {
        guard retentionDays > 0 else {
            deleteAll()
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .now
        do {
            try context.delete(
                model: Transcript.self,
                where: #Predicate { $0.createdAt < cutoff }
            )
            save()
        } catch {
            logger.error("Could not prune history: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func deleteAll() {
        do {
            try context.delete(model: Transcript.self)
            save()
        } catch {
            logger.error("Could not clear history: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func delete(_ transcript: Transcript) {
        context.delete(transcript)
        save()
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
