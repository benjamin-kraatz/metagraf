#if os(macOS)
import Foundation
import MetagrafCore
import SwiftUI

/// Chooses the perspective and rewrite strength used during AI refinement.
struct PersonasSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Persona") {
                Picker("Write as a", selection: $settings.refinementPersona) {
                    ForEach(RefinementPersona.allCases) { persona in
                        Text(LocalizedStringKey(persona.displayName)).tag(persona)
                    }
                }

                Text(LocalizedStringKey(settings.refinementPersona.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Adaptation") {
                Picker("Strength", selection: $settings.personaAdaptation) {
                    ForEach(PersonaAdaptation.allCases) { adaptation in
                        Text(LocalizedStringKey(adaptation.displayName)).tag(adaptation)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(settings.refinementPersona == .none)

                Text(adaptationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Apple Intelligence") {
                Text(
                    """
                    Personas enhance every formatting style except “Exactly as spoken”. \
                    Refinement requires Apple Intelligence and is performed entirely on-device.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var adaptationExplanation: LocalizedStringKey {
        if settings.refinementPersona == .none {
            "Select a persona to choose how strongly it shapes the wording."
        } else {
            LocalizedStringKey(settings.personaAdaptation.explanation)
        }
    }
}

#if DEBUG
@MainActor
private func previewPersonasSettings() -> SettingsStore {
    let suite = "Metagraf.PersonasSettingsPreview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set(RefinementPersona.programmer.rawValue, forKey: "refinement.persona")
    return SettingsStore(defaults: defaults)
}

#Preview {
    PersonasSettings(settings: previewPersonasSettings())
        .frame(width: 580, height: 460)
}
#endif
#endif
