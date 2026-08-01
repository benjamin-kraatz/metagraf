import AVFoundation
import Foundation
import OSLog

/// Drives one dictation from hotkey press to finished text.
///
/// Everything the UI shows — the pill, the menu bar icon — is derived from
/// `phase`, `liveText`, and `level`, so there is a single source of truth for
/// what the app is doing.
@MainActor
@Observable
public final class DictationSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case recording
        case transcribing
        case refining
        case inserting
        case failed(String)

        public var isBusy: Bool {
            switch self {
            case .idle, .failed: false
            case .preparing, .recording, .transcribing, .refining, .inserting: true
            }
        }
    }

    public private(set) var phase: Phase = .idle

    /// Text heard so far, updated while the user is still speaking.
    public private(set) var liveText = ""

    /// Normalized microphone loudness, 0…1.
    public private(set) var level: Float = 0

    /// The most recent completed transcript, after refinement.
    public private(set) var lastTranscript = ""

    /// What the engine heard before refinement, kept so a bad rewrite can be
    /// compared against the original.
    public private(set) var lastRawTranscript = ""

    /// When the current recording began, for the pill's elapsed-time readout.
    public private(set) var recordingStartedAt: Date?

    /// Locale and vocabulary for the next utterance.
    public var configuration: EngineConfiguration

    /// How the transcript should be tidied before delivery.
    public var refinement: RefinementContext = RefinementContext(style: .cleanup)

    /// The refinement chain. Replaceable so tests can bypass the language model.
    public var refiners = RefinerRegistry()

    /// Delivers each finished transcript, typically by inserting it into the
    /// frontmost application. Throwing surfaces the reason in the pill, which
    /// matters because delivery is the step most likely to be blocked by
    /// something outside the app's control.
    public var deliver: ((String) async throws -> Void)?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Dictation")
    private let capture: AudioCaptureEngine
    private var engine: any TranscriptionEngine

    private var pumpTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var levelsTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    public init(
        capture: AudioCaptureEngine = AudioCaptureEngine(),
        engine: any TranscriptionEngine = AppleSpeechEngine(),
        configuration: EngineConfiguration = EngineConfiguration(locale: .current)
    ) {
        self.capture = capture
        self.engine = engine
        self.configuration = configuration

        levelsTask = Task { [weak self] in
            guard let self else { return }
            for await value in capture.levels {
                self.level = value
            }
        }
    }

    isolated deinit {
        levelsTask?.cancel()
        pumpTask?.cancel()
        updatesTask?.cancel()
        recoveryTask?.cancel()
    }

    /// Allocates audio and model resources so the next `begin` is instant.
    public func prewarm() {
        capture.prewarm()
    }

    /// The backend currently in use.
    public var engineIdentifier: EngineID { engine.identifier }

    /// Swaps the transcription backend. Ignored mid-dictation, so changing the
    /// model in Settings never cuts off an utterance in progress.
    public func use(_ newEngine: any TranscriptionEngine) {
        guard !phase.isBusy else { return }
        engine = newEngine
        logger.info("Switched to \(newEngine.identifier.rawValue, privacy: .public)")
    }

    /// Starts listening. Safe to call when already recording — it does nothing.
    public func begin() async {
        guard !phase.isBusy else { return }

        recoveryTask?.cancel()
        phase = .preparing
        liveText = ""

        guard await MicrophoneAuthorization.request() else {
            fail(with: AudioCaptureEngine.CaptureError.microphoneAccessDenied)
            return
        }

        do {
            try await engine.prepare(configuration)
            let format = await engine.preferredAudioFormat()
            let audio = try capture.start(convertingTo: format)

            phase = .recording
            recordingStartedAt = .now

            pumpTask = Task { [engine] in
                for await chunk in audio {
                    await engine.append(chunk)
                }
            }

            if engine.producesLiveText {
                updatesTask = Task { [weak self, engine] in
                    guard let self else { return }
                    do {
                        for try await update in await engine.updates() {
                            self.liveText = update.text
                        }
                    } catch {
                        self.logger.error("Live updates ended: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            fail(with: error)
        }
    }

    /// Stops listening and produces the transcript.
    public func complete() async {
        guard phase == .recording else { return }

        phase = .transcribing
        recordingStartedAt = nil
        capture.stop()

        // Wait for the capture stream to drain so the last buffers reach the
        // engine before it finalizes.
        await pumpTask?.value
        pumpTask = nil

        do {
            let heard = try await engine.finish()
            updatesTask?.cancel()
            updatesTask = nil

            lastRawTranscript = heard

            guard !heard.isEmpty else {
                logger.debug("Utterance produced no text")
                liveText = ""
                phase = .idle
                return
            }

            phase = .refining
            let transcript = await refiners.refine(heard, context: refinement)

            lastTranscript = transcript
            liveText = transcript

            phase = .inserting
            try await deliver?(transcript)
            phase = .idle
        } catch {
            fail(with: error)
        }
    }

    /// Throws the current utterance away without producing text.
    public func abort() async {
        guard phase.isBusy else { return }

        capture.stop()
        pumpTask?.cancel()
        pumpTask = nil
        updatesTask?.cancel()
        updatesTask = nil
        await engine.cancel()

        liveText = ""
        recordingStartedAt = nil
        phase = .idle
    }

    private func fail(with error: any Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.error("Dictation failed: \(message, privacy: .public)")

        capture.stop()
        pumpTask?.cancel()
        pumpTask = nil
        updatesTask?.cancel()
        updatesTask = nil
        recordingStartedAt = nil
        phase = .failed(message)

        // Clear the error on its own so a transient failure does not leave the
        // pill stuck showing it.
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, case .failed = self.phase else { return }
            self.phase = .idle
        }
    }
}
