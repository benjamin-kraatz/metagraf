#if os(macOS)
import MetagrafCore
import SwiftUI

/// Preferences window. Tabs are filled in during M3.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Text("General settings arrive in M3.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }

            Tab("Dictation", systemImage: "mic") {
                Form {
                    Text("Hotkey and audio settings arrive in M3.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 560, height: 420)
    }
}

#Preview {
    SettingsView()
}
#endif
