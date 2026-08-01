import Foundation
import Testing

@testable import MetagrafCore

@MainActor
private func makeStore() -> RecentTranscripts {
    RecentTranscripts(defaults: UserDefaults(suiteName: "MetagrafTests.\(UUID().uuidString)")!)
}

@Suite("Recent transcripts")
@MainActor
struct RecentTranscriptsTests {
    @Test("Newest dictation comes first")
    func newestFirst() {
        let store = makeStore()
        store.add("first")
        store.add("second")

        #expect(store.all().map(\.text) == ["second", "first"])
    }

    @Test("Saying the same thing again moves it up rather than duplicating")
    func repeatsMoveUp() {
        let store = makeStore()
        store.add("hello")
        store.add("goodbye")
        store.add("hello")

        #expect(store.all().map(\.text) == ["hello", "goodbye"])
    }

    @Test("The list stays bounded so the keyboard stays cheap to load")
    func staysBounded() {
        let store = makeStore()
        for index in 0..<(RecentTranscripts.limit + 10) {
            store.add("entry \(index)")
        }

        let all = store.all()
        #expect(all.count == RecentTranscripts.limit)
        #expect(all.first?.text == "entry \(RecentTranscripts.limit + 9)")
    }

    @Test("Blank dictations are not recorded")
    func ignoresBlanks() {
        let store = makeStore()
        store.add("   ")
        store.add("\n")
        #expect(store.all().isEmpty)
    }

    @Test("Surrounding whitespace is trimmed before storing")
    func trimsWhitespace() {
        let store = makeStore()
        store.add("  hello there\n")
        #expect(store.all().first?.text == "hello there")
    }

    @Test("Entries can be removed individually and all at once")
    func removal() {
        let store = makeStore()
        store.add("one")
        store.add("two")

        guard let first = store.all().first else {
            Issue.record("expected an entry")
            return
        }
        store.remove(first)
        #expect(store.all().map(\.text) == ["one"])

        store.clear()
        #expect(store.all().isEmpty)
    }

    @Test("A separate store sees what another wrote, as the keyboard must")
    func sharedAcrossInstances() {
        let defaults = UserDefaults(suiteName: "MetagrafTests.\(UUID().uuidString)")!
        RecentTranscripts(defaults: defaults).add("from the app")

        #expect(RecentTranscripts(defaults: defaults).all().map(\.text) == ["from the app"])
    }
}
