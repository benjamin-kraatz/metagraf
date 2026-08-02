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

                    Slider(value: adaptationValue, in: adaptationRange, step: 1) {
                        Text("Strength")
                    }
                    .labelsHidden()

                    adaptationLabels
                }
                .disabled(settings.refinementPersona == .none)

                Text(adaptationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.usesPromptingRefinement {
                    Divider()

                    Toggle("Use nearby app context", isOn: $settings.usesNearbyAppContext)
                    Text(
                        """
                        When enabled, Metagraf reads selected and nearby text from the focused field \
                        when dictation starts. Relevant identifiers and short excerpts may be included \
                        in the refined prompt. Neither the captured context nor Prompting dictations \
                        are saved to History.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
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

    private var adaptationRange: ClosedRange<Double> {
        0...Double(PersonaAdaptation.allCases.count - 1)
    }

    private var adaptationLabels: some View {
        GeometryReader { geometry in
            let adaptations = PersonaAdaptation.allCases
            let segmentWidth = geometry.size.width / CGFloat(adaptations.count - 1)
            let labelWidth = segmentWidth * 0.82

            ForEach(adaptations.indices, id: \.self) { index in
                let alignment = adaptationLabelAlignment(at: index, count: adaptations.count)

                adaptationLabel(adaptations[index], alignment: alignment)
                    .frame(width: labelWidth, alignment: alignment)
                    .position(
                        x: adaptationLabelPosition(
                            at: index,
                            count: adaptations.count,
                            segmentWidth: segmentWidth,
                            labelWidth: labelWidth
                        ),
                        y: geometry.size.height / 2
                    )
            }
        }
        // Match the slider's thumb-center inset and reserve equal height when
        // a localized label needs a second line.
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func adaptationLabel(
        _ adaptation: PersonaAdaptation,
        alignment: Alignment
    ) -> some View {
        Text(LocalizedStringKey(adaptation.displayName))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(textAlignment(for: alignment))
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func adaptationLabelAlignment(at index: Int, count: Int) -> Alignment {
        if index == 0 {
            return .leading
        }
        if index == count - 1 {
            return .trailing
        }
        return .center
    }

    private func adaptationLabelPosition(
        at index: Int,
        count: Int,
        segmentWidth: CGFloat,
        labelWidth: CGFloat
    ) -> CGFloat {
        if index == 0 {
            return labelWidth / 2
        }
        if index == count - 1 {
            return segmentWidth * CGFloat(count - 1) - labelWidth / 2
        }
        return segmentWidth * CGFloat(index)
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
