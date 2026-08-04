#if os(iOS)
import MetagrafCore
import SwiftUI

/// Portable persona controls. Nearby-field context intentionally remains macOS-only.
struct PersonaSettingsView: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    var body: some View {
        Form {
            if !availability.allowsLanguageModel {
                Section {
                    Label("Apple Intelligence is unavailable for the selected language.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Persona") {
                Picker("Write as a", selection: $settings.refinementPersona) {
                    ForEach(RefinementPersona.allCases) { persona in
                        Text(LocalizedStringKey(persona.displayName)).tag(persona)
                    }
                }
                .pickerStyle(.menu)

                Text(LocalizedStringKey(settings.refinementPersona.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Strength", selection: $settings.personaAdaptation) {
                    ForEach(PersonaAdaptation.allCases) { adaptation in
                        Text(LocalizedStringKey(adaptation.displayName)).tag(adaptation)
                    }
                }
                .pickerStyle(.menu)
                .disabled(settings.refinementPersona == .none)

                Text(adaptationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Adaptation")
            } footer: {
                Text("Personas guide terminology and tone while keeping your meaning. They apply to every style except “Exactly as spoken.”")
            }
        }
        .disabled(!availability.allowsLanguageModel || settings.refinementStyle == .raw)
        .navigationTitle("Persona & Adaptation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var adaptationExplanation: LocalizedStringKey {
        if settings.refinementPersona == .none {
            "Select a persona to choose how strongly it shapes the wording."
        } else {
            LocalizedStringKey(settings.personaAdaptation.explanation)
        }
    }
}

#Preview {
    NavigationStack {
        PersonaSettingsView(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "PersonaPreview")!),
            availability: RefinementAvailabilityModel(state: .available)
        )
    }
}
#endif
