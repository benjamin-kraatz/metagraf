import AVFoundation
import Foundation

/// Stable identifier for a transcription backend.
public struct EngineID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Apple's on-device `SpeechAnalyzer`. No download, lowest latency, live text.
    public static let appleSpeech = EngineID(rawValue: "apple.speech")

    /// Whisper models running through CoreML. Buffered, higher accuracy.
    public static let whisperKit = EngineID(rawValue: "whisperkit")
}

/// A snapshot of what an engine has heard so far.
public struct TranscriptionUpdate: Sendable, Equatable {
    /// Text the engine has committed to. It will not change.
    public var finalized: AttributedString

    /// Text the engine may still revise as more audio arrives.
    public var volatile: AttributedString

    public init(finalized: AttributedString = "", volatile: AttributedString = "") {
        self.finalized = finalized
        self.volatile = volatile
    }

    /// Everything heard so far, committed and not.
    public var text: String {
        String(finalized.characters) + String(volatile.characters)
    }
}

/// Everything an engine needs before audio starts flowing.
public struct EngineConfiguration: Sendable {
    public var locale: Locale

    /// Names, jargon, and product terms that should bias recognition. Apple's
    /// engine takes these directly, which handles most vocabulary needs without
    /// involving a language model afterwards.
    public var contextualStrings: [String]

    public init(locale: Locale, contextualStrings: [String] = []) {
        self.locale = locale
        self.contextualStrings = contextualStrings
    }
}

public enum TranscriptionError: Error, Sendable, Equatable {
    case localeNotSupported(Locale)
    case assetsUnavailable(Locale)
    case notPrepared
    case engineUnavailable(String)
}

extension TranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .localeNotSupported(let locale):
            let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            let format = String(localized: "%@ isn’t supported by this model.", bundle: .main)
            return String(format: format, name)
        case .assetsUnavailable(let locale):
            let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            let format = String(localized: "The speech model for %@ couldn’t be downloaded.", bundle: .main)
            return String(format: format, name)
        case .notPrepared:
            return String(localized: "The transcription engine wasn’t ready.", bundle: .main)
        case .engineUnavailable(let reason):
            return reason
        }
    }
}

/// A speech-to-text backend.
///
/// The lifecycle for one utterance is `prepare` → `updates` → repeated `append`
/// → `finish` (or `cancel`). Implementations are actors, so every requirement
/// is reachable with `await`.
public protocol TranscriptionEngine: Sendable {
    var identifier: EngineID { get }

    /// Whether the engine emits text while audio is still arriving, which lets
    /// the pill show words as they are spoken. Buffered engines such as
    /// WhisperKit report `false` and produce text only from `finish()`.
    var producesLiveText: Bool { get }

    /// Format the engine wants buffers in, valid after `prepare`. `nil` means
    /// the engine accepts whatever the microphone produces.
    func preferredAudioFormat() async -> AVAudioFormat?

    /// Loads models and gets ready for a new utterance.
    func prepare(_ configuration: EngineConfiguration) async throws

    /// Live updates for the utterance most recently prepared.
    func updates() async -> AsyncThrowingStream<TranscriptionUpdate, any Error>

    /// Feeds captured audio, already converted to `preferredAudioFormat`.
    func append(_ audio: CapturedAudio) async

    /// Stops capture and returns the complete transcript.
    func finish() async throws -> String

    /// Abandons the utterance without producing a transcript.
    func cancel() async
}
