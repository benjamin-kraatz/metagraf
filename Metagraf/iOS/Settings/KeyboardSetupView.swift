#if os(iOS)
import SwiftUI
import UIKit

/// Explains the two steps iOS requires before the keyboard works.
struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section {
                StepRow(
                    number: 1,
                    title: "Add the keyboard",
                    detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Metagraf."
                )
                StepRow(
                    number: 2,
                    title: "Turn on Full Access",
                    detail: "Tap Metagraf in that list and enable Allow Full Access."
                )
            } header: {
                Text("Insert what you dictated, without leaving the app you’re typing in")
            } footer: {
                Text(
                    """
                    The keyboard doesn’t record — iOS doesn’t allow keyboards to \
                    use the microphone. Dictate here in Metagraf, then tap the \
                    Metagraf keyboard anywhere to drop that text in. Full Access \
                    is what lets it read your transcripts. Nothing leaves this device.
                    """
                )
            }

            Section {
                Text("Add “Start Dictation” to your Action Button, Control Centre, or a Shortcut to begin dictating in one press.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Faster ways in")
            }

            Section {
                Button("Open Metagraf Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
        .navigationTitle("Keyboard & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StepRow: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number.formatted())
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { KeyboardSetupView() }
}
#endif
