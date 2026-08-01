import AVFoundation
import Foundation
import OSLog
import WhisperKit

/// Transcription through Whisper models running on CoreML.
///
/// Unlike Apple's engine this one is buffered: Whisper works on a complete
/// window of audio, so nothing is produced until the user stops speaking. The
/// pill shows a spinner rather than live text for it, which `producesLiveText`
/// signals to the rest of the app.
public actor WhisperKitEngine: TranscriptionEngine {
    public nonisolated var identifier: EngineID { .whisperKit }
    public nonisolated var producesLiveText: Bool { false }

    /// Whisper models are trained on 16 kHz mono audio.
    private static let requiredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "WhisperKit")
    private let modelID: String
    private let modelFolder: URL?

    private var pipeline: Pipeline?
    private var samples: [Float] = []
    private var locale: Locale = .current

    /// Owns the `WhisperKit` instance and performs the call itself.
    ///
    /// `WhisperKit` is not annotated `Sendable`, so awaiting its methods from
    /// inside this actor would mean sending actor state across isolation. Here
    /// the instance never leaves the box: the transcription runs nonisolated,
    /// one utterance at a time, which is how the engine is driven anyway.
    private final class Pipeline: @unchecked Sendable {
        private let whisperKit: WhisperKit

        init(_ whisperKit: WhisperKit) {
            self.whisperKit = whisperKit
        }

        func transcribe(_ audio: [Float], options: DecodingOptions) async throws -> String {
            let results = try await whisperKit.transcribe(audioArray: audio, decodeOptions: options)
            return results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public init(modelID: String, modelFolder: URL?) {
        self.modelID = modelID
        self.modelFolder = modelFolder
    }

    public func preferredAudioFormat() -> AVAudioFormat? {
        Self.requiredFormat
    }

    public func prepare(_ configuration: EngineConfiguration) async throws {
        locale = configuration.locale
        samples.removeAll(keepingCapacity: true)

        // Loading weights costs seconds, so the pipeline is kept between
        // utterances rather than rebuilt for each one.
        guard pipeline == nil else { return }

        guard let modelFolder else {
            let format = String(localized: "The %@ model isn’t downloaded yet.", bundle: .main)
            throw TranscriptionError.engineUnavailable(
                String(format: format, modelID)
            )
        }

        do {
            let config = WhisperKitConfig(
                model: modelID,
                modelFolder: modelFolder.path(percentEncoded: false),
                // Never fetch mid-dictation; downloads are an explicit action in
                // the models list, where progress is visible.
                download: false
            )
            pipeline = Pipeline(try await WhisperKit(config))
            logger.info("Loaded \(self.modelID, privacy: .public)")
        } catch {
            let format = String(localized: "The %@ model could not be loaded.", bundle: .main)
            throw TranscriptionError.engineUnavailable(
                String(format: format, modelID)
            )
        }
    }

    public func updates() -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        // Buffered: nothing to report until `finish`.
        AsyncThrowingStream { $0.finish() }
    }

    public func append(_ audio: CapturedAudio) {
        let buffer = audio.buffer
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    public func finish() async throws -> String {
        guard let pipeline else { throw TranscriptionError.notPrepared }

        let audio = samples
        samples.removeAll(keepingCapacity: true)
        guard !audio.isEmpty else { return "" }

        let options = DecodingOptions(
            language: locale.language.languageCode?.identifier,
            temperature: 0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        return try await pipeline.transcribe(audio, options: options)
    }

    public func cancel() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Frees the loaded weights. Called when the user picks a different model.
    public func unload() {
        pipeline = nil
        samples.removeAll(keepingCapacity: false)
    }
}
