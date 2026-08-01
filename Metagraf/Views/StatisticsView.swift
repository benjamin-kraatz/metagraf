import MetagrafCore
import SwiftData
import SwiftUI

// MARK: - Statistics

struct StatisticsView: View {
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
                        StatTile(title: "Average pace", value: String(localized: "\(averageWordsPerMinute) wpm"))
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

struct StatTile: View {
    let title: LocalizedStringKey
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
