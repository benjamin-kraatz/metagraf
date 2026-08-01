#if os(macOS)
import MetagrafCore
import MetagrafWhisper
import SwiftUI

/// Chooses which speech model dictation uses, and manages what is on disk.
struct ModelsSettings: View {
    @Bindable var settings: SettingsStore
    let models: ModelStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(ModelCatalog.all) { model in
                        ModelRow(model: model, settings: settings, models: models)
                    }
                }
                .padding(14)
            }

            Divider()

            HStack {
                Text("Downloaded models use \(formattedDiskUsage).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { models.refresh() }
    }

    private var formattedDiskUsage: String {
        models.diskUsage().formatted(.byteCount(style: .file))
    }
}

private struct ModelRow: View {
    let model: ModelDescriptor
    @Bindable var settings: SettingsStore
    let models: ModelStore

    private var state: ModelStore.State { models.state(of: model) }
    private var isSelected: Bool { settings.modelID == model.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: select) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .disabled(!state.isInstalled)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.headline)
                    if !model.isMultilingual {
                        Tag(text: "English only")
                    }
                    if model.engine == .appleSpeech {
                        Tag(text: "Live text")
                    }
                }

                Text(LocalizedStringKey(model.summary))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Metric(label: "Speed", tier: model.speed)
                    Metric(label: "Accuracy", tier: model.accuracy)
                    if model.requiresDownload {
                        Text(model.downloadBytes.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("· \(model.recommendedMemoryGB) GB RAM suggested")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .failed(let message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            action
        }
        .padding(13)
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.35)),
            in: .rect(cornerRadius: 12)
        )
        .contentShape(.rect)
        .onTapGesture(perform: select)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .installed where model.requiresDownload:
            Button("Remove") { models.delete(model) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isSelected)

        case .installed:
            EmptyView()

        case .notInstalled, .failed:
            Button("Download") { models.download(model) }
                .buttonStyle(.glass)
                .controlSize(.small)

        case .downloading(let fraction):
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 96)
                Button("Cancel") { models.cancelDownload(of: model) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func select() {
        guard state.isInstalled else { return }
        settings.modelID = model.id
    }
}

private struct Tag: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}

private struct Metric: View {
    let label: LocalizedStringKey
    let tier: ModelDescriptor.Tier

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(tier.label))
                .font(.caption.weight(.medium))
        }
    }
}
#endif
