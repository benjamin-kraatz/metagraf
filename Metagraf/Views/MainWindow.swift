import MetagrafCore
import SwiftData
import SwiftUI

/// The management window: what you have dictated, and how much.
struct MainWindow: View {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case history
        case statistics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: "History"
            case .statistics: "Statistics"
            }
        }

        var symbol: String {
            switch self {
            case .history: "clock"
            case .statistics: "chart.bar"
            }
        }
    }

    @State private var selection: Section = .history

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch selection {
            case .history: HistoryList()
            case .statistics: StatisticsView()
            }
        }
        .navigationTitle("Metagraf")
    }
}

// MARK: - History

private struct HistoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var search = ""

    private var filtered: [Transcript] {
        guard !search.isEmpty else { return transcripts }
        return transcripts.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if transcripts.isEmpty {
                ContentUnavailableView(
                    "Nothing dictated yet",
                    systemImage: "waveform",
                    description: Text("Hold the dictation key anywhere and start talking.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(filtered) { transcript in
                        TranscriptRow(transcript: transcript)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $search, prompt: "Search transcripts")
        .navigationTitle("History")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(filtered[index])
        }
        try? context.save()
    }
}

private struct TranscriptRow: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transcript.text)
                .textSelection(.enabled)
                .lineLimit(4)

            HStack(spacing: 8) {
                Text(transcript.createdAt, format: .relative(presentation: .named))
                if let app = transcript.appName {
                    Text("·")
                    Text(app)
                }
                Text("·")
                Text("^[\(transcript.wordCount) word](inflect: true)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") { copy(transcript.text) }
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Statistics

private struct StatisticsView: View {
    @Query private var transcripts: [Transcript]

    /// Sustained typing is commonly put around 40 words per minute, which is
    /// the baseline the "time saved" figure compares dictation against.
    private static let typingWordsPerMinute = 40.0

    private var totalWords: Int {
        transcripts.reduce(0) { $0 + $1.wordCount }
    }

    private var totalSeconds: Double {
        transcripts.reduce(0) { $0 + $1.durationSeconds }
    }

    private var averageWordsPerMinute: Int {
        guard totalSeconds > 0 else { return 0 }
        return Int((Double(totalWords) / totalSeconds) * 60)
    }

    /// How much longer typing those words would plausibly have taken.
    private var secondsSaved: Double {
        max(0, (Double(totalWords) / Self.typingWordsPerMinute) * 60 - totalSeconds)
    }

    var body: some View {
        Group {
            if transcripts.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.bar",
                    description: Text("They appear once you have dictated something.")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190), spacing: 16)],
                        spacing: 16
                    ) {
                        StatTile(title: "Dictations", value: transcripts.count.formatted())
                        StatTile(title: "Words", value: totalWords.formatted())
                        StatTile(title: "Average pace", value: "\(averageWordsPerMinute) wpm")
                        StatTile(
                            title: "Time saved vs. typing",
                            value: Duration.seconds(secondsSaved)
                                .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
                        )
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Statistics")
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}
