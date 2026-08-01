import AVFoundation
import Foundation
import OSLog
import Speech

/// Transcription through Apple's on-device `SpeechAnalyzer`.
///
/// This is the default engine: it needs no model download beyond a per-locale
/// system asset, runs out of process, and emits text while the user is still
/// speaking, which is what makes the pill feel live.
public actor AppleSpeechEngine: TranscriptionEngine {
    public nonisolated var identifier: EngineID { .appleSpeech }
    public nonisolated var producesLiveText: Bool { true }

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "AppleSpeech")

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var updateStream: AsyncThrowingStream<TranscriptionUpdate, any Error>?
    private var updateContinuation: AsyncThrowingStream<TranscriptionUpdate, any Error>.Continuation?
    private var relayTask: Task<Void, Never>?

    private var audioFormat: AVAudioFormat?
    private var finalized = AttributedString()
    private var volatileText = AttributedString()

    public init() {}

    public func preferredAudioFormat() -> AVAudioFormat? {
        audioFormat
    }

    public func prepare(_ configuration: EngineConfiguration) async throws {
        await teardown()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: configuration.locale) else {
            throw TranscriptionError.localeNotSupported(configuration.locale)
        }

        // `.progressiveTranscription` reports volatile results, which is what
        // lets the pill show words before the user stops talking.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await Self.installAssetsIfNeeded(for: transcriber, locale: locale)

        let context = AnalysisContext()
        if !configuration.contextualStrings.isEmpty {
            context.contextualStrings[.general] = configuration.contextualStrings
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .unbounded
        )
        let analyzer = SpeechAnalyzer(
            inputSequence: inputSequence,
            modules: [transcriber],
            analysisContext: context
        )

        let format = Self.bestFormat(from: await transcriber.availableCompatibleAudioFormats)
        try await analyzer.prepareToAnalyze(in: format)

        let (updates, updateContinuation) = AsyncThrowingStream<TranscriptionUpdate, any Error>.makeStream()

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = inputContinuation
        self.audioFormat = format
        self.updateStream = updates
        self.updateContinuation = updateContinuation
        self.finalized = AttributedString()
        self.volatileText = AttributedString()

        // One long-lived relay so `finish()` can wait for every result to land
        // before reporting the transcript.
        relayTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    await self.absorb(result)
                }
                await self?.closeUpdates(throwing: nil)
            } catch {
                await self?.closeUpdates(throwing: error)
            }
        }

        logger.debug(
            """
            Prepared for \(locale.identifier, privacy: .public) \
            at \(format?.sampleRate ?? 0, privacy: .public) Hz
            """
        )
    }

    /// Picks the highest-fidelity format the transcriber will accept.
    ///
    /// The list is not ordered by quality: its first entry can be 8 kHz
    /// telephone-grade audio, which throws away most of the frequency range
    /// speech recognition relies on.
    private static func bestFormat(from formats: [AVAudioFormat]) -> AVAudioFormat? {
        formats.max { $0.sampleRate < $1.sampleRate }
    }

    public func updates() -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        updateStream ?? AsyncThrowingStream { $0.finish() }
    }

    public func append(_ audio: CapturedAudio) {
        inputContinuation?.yield(AnalyzerInput(buffer: audio.buffer))
    }

    public func finish() async throws -> String {
        guard let analyzer else { throw TranscriptionError.notPrepared }

        inputContinuation?.finish()
        inputContinuation = nil

        try await analyzer.finalizeAndFinishThroughEndOfInput()
        // The relay outlives the analyzer by a moment; waiting for it is what
        // guarantees the returned text includes the final result.
        await relayTask?.value

        let transcript = String(finalized.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        await teardown()
        return transcript
    }

    public func cancel() async {
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        await teardown()
    }

    // MARK: - Internals

    private func absorb(_ result: SpeechTranscriber.Result) {
        if result.isFinal {
            finalized.append(result.text)
            volatileText = AttributedString()
        } else {
            volatileText = result.text
        }
        updateContinuation?.yield(TranscriptionUpdate(finalized: finalized, volatile: volatileText))
    }

    private func closeUpdates(throwing error: (any Error)?) {
        if let error {
            updateContinuation?.finish(throwing: error)
        } else {
            updateContinuation?.finish()
        }
        updateContinuation = nil
    }

    private func teardown() async {
        relayTask?.cancel()
        relayTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        closeUpdates(throwing: nil)
        updateStream = nil
        analyzer = nil
        transcriber = nil
    }

    /// Downloads the system speech asset for a locale if it is not present yet.
    private static func installAssetsIfNeeded(
        for transcriber: SpeechTranscriber,
        locale: Locale
    ) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            break
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                break
            }
            try await request.downloadAndInstall()
        case .unsupported:
            throw TranscriptionError.localeNotSupported(locale)
        @unknown default:
            break
        }

        // Reserving keeps the asset resident; the system caps how many locales
        // an app may hold, so a failure here is not fatal.
        _ = try? await AssetInventory.reserve(locale: locale)
    }
}
