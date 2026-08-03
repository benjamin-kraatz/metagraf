#if os(iOS)
import SwiftUI

/// Top-level iOS navigation.
struct RootView: View {
    let controller: DictationController

    var body: some View {
        TabView {
            Tab("Dictate", systemImage: "mic") {
                DictateView(controller: controller)
            }

            Tab("History", systemImage: "clock") {
                NavigationStack {
                    HistoryList()
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    MobileSettingsView(
                        settings: controller.settings,
                        availability: controller.refinementAvailability
                    )
                }
            }
        }
    }
}
#endif
