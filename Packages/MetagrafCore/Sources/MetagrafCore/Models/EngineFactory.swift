import Foundation

/// Builds the transcription backend a chosen model needs.
public enum EngineFactory {
    @MainActor
    public static func make(for model: ModelDescriptor, store: ModelStore) -> any TranscriptionEngine {
        switch model.engine {
        case .whisperKit:
            WhisperKitEngine(modelID: model.id, modelFolder: store.folder(for: model))
        default:
            AppleSpeechEngine()
        }
    }

    /// The model to actually use, falling back to Apple's engine when the
    /// chosen one is not on disk. Dictating with a silently different model
    /// would be worse than the fallback being visible in Settings.
    @MainActor
    public static func resolve(modelID: String, store: ModelStore) -> ModelDescriptor {
        guard
            let model = ModelCatalog.model(withID: modelID),
            store.state(of: model).isInstalled
        else {
            return ModelCatalog.default
        }
        return model
    }
}
