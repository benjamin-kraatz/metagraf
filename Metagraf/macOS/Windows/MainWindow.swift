#if os(macOS)
import MetagrafCore
import SwiftData
import SwiftUI

/// The management window: what you have dictated, and how much.
struct MainWindow: View {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case history
        case statistics

        var id: String { rawValue }

        var title: LocalizedStringKey {
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
#endif
