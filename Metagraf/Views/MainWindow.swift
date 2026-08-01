import MetagrafCore
import SwiftUI

/// Placeholder shell for the management window. Sections are filled in during M3.
struct MainWindow: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("History", systemImage: "clock")
                Label("Models", systemImage: "cube")
                Label("Vocabulary", systemImage: "character.book.closed")
                Label("Statistics", systemImage: "chart.bar")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ContentUnavailableView(
                "Metagraf",
                systemImage: "waveform",
                description: Text("Hold the dictation hotkey anywhere to start talking.")
            )
        }
    }
}

#Preview {
    MainWindow()
        .frame(width: 900, height: 600)
}
