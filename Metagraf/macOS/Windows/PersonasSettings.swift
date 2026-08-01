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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Strength")

                    Slider(value: adaptationValue, in: 0...2, step: 1) {
                        Text("Strength")
                    }
                    .labelsHidden()

                    HStack(alignment: .top, spacing: 0) {
                        adaptationLabel(.minimalCorrection, alignment: .leading)
                        adaptationLabel(.contextualPolish, alignment: .center)
                        adaptationLabel(.strongAdaptation, alignment: .trailing)
                    }
                }
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

    private var adaptationValue: Binding<Double> {
        Binding(
            get: {
                let index = PersonaAdaptation.allCases.firstIndex(of: settings.personaAdaptation) ?? 1
                return Double(index)
            },
            set: { value in
                let index = min(max(Int(value.rounded()), 0), PersonaAdaptation.allCases.count - 1)
                settings.personaAdaptation = PersonaAdaptation.allCases[index]
            }
        )
    }

    private func adaptationLabel(
        _ adaptation: PersonaAdaptation,
        alignment: Alignment
    ) -> some View {
        Text(LocalizedStringKey(adaptation.displayName))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(textAlignment(for: alignment))
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func textAlignment(for alignment: Alignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
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
