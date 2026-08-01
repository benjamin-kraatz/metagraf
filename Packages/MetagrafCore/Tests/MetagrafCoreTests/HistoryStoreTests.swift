import Foundation
import SwiftData
import Testing

@testable import MetagrafCore

@Suite("History")
@MainActor
struct HistoryStoreTests {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(inMemory: true)
    }

    private func count(in store: HistoryStore) throws -> Int {
        try store.container.mainContext.fetch(FetchDescriptor<Transcript>()).count
    }

    private func transcript(daysAgo: Int, text: String = "hello there") -> Transcript {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Transcript(
            createdAt: date,
            text: text,
            localeIdentifier: "en_US",
            engineIdentifier: EngineID.appleSpeech.rawValue,
            durationSeconds: 3
        )
    }

    @Test("Transcripts are kept when retention allows it")
    func recordsWhenRetentionAllows() throws {
        let store = try makeStore()
        store.record(transcript(daysAgo: 0), retentionDays: 30)
        #expect(try count(in: store) == 1)
    }

    @Test("Nothing is written down when retention is off")
    func recordsNothingWhenRetentionIsZero() throws {
        let store = try makeStore()
        store.record(transcript(daysAgo: 0), retentionDays: 0)
        #expect(try count(in: store) == 0)
    }

    @Test("Entries past the retention window are pruned")
    func prunesOldEntries() throws {
        let store = try makeStore()
        store.record(transcript(daysAgo: 1, text: "recent"), retentionDays: 90)
        store.record(transcript(daysAgo: 45, text: "old"), retentionDays: 90)
        #expect(try count(in: store) == 2)

        store.prune(retentionDays: 30)

        let remaining = try store.container.mainContext.fetch(FetchDescriptor<Transcript>())
        #expect(remaining.map(\.text) == ["recent"])
    }

    @Test("Turning retention off clears what was already stored")
    func pruningWithZeroClearsEverything() throws {
        let store = try makeStore()
        store.record(transcript(daysAgo: 0), retentionDays: 30)
        #expect(try count(in: store) == 1)

        store.prune(retentionDays: 0)
        #expect(try count(in: store) == 0)
    }

    @Test("Word count and pace are derived from the text")
    func derivesWordCountAndPace() {
        let entry = Transcript(
            text: "one two three four five six",
            localeIdentifier: "en_US",
            engineIdentifier: EngineID.appleSpeech.rawValue,
            durationSeconds: 6
        )

        #expect(entry.wordCount == 6)
        #expect(entry.wordsPerMinute == 60)
    }

    @Test("Pace is zero rather than infinite for a zero-length recording")
    func zeroDurationDoesNotDivideByZero() {
        let entry = Transcript(
            text: "hello",
            localeIdentifier: "en_US",
            engineIdentifier: EngineID.appleSpeech.rawValue,
            durationSeconds: 0
        )

        #expect(entry.wordsPerMinute == 0)
    }
}
