import MetagrafCore
import SwiftData
import SwiftUI

// MARK: - History

struct HistoryList: View {
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

struct TranscriptRow: View {
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
