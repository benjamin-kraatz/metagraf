import AVFoundation
import Foundation
import OSLog

/// Microphone capture for one dictation utterance.
///
/// The engine is only running while the user is actually dictating. Keeping it
/// running to buffer "pre-roll" audio would light the system microphone
/// indicator permanently, which is the wrong trade for a dictation app people
/// leave running all day. Start latency is handled by `prewarm()` instead,
/// which allocates the audio graph up front so `start` costs milliseconds.
@MainActor
public final class AudioCaptureEngine {
    public enum CaptureError: Error, LocalizedError, Equatable {
        case microphoneAccessDenied
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied:
                "Metagraf needs microphone access to hear you."
            case .unsupportedFormat:
                "The selected input device produced an unusable audio format."
            }
        }
    }

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "AudioCapture")
    private let engine = AVAudioEngine()
    private var audioContinuation: AsyncStream<CapturedAudio>.Continuation?
    private let levelContinuation: AsyncStream<Float>.Continuation

    /// Normalized microphone loudness, for the pill's meter. Stays alive across
    /// utterances so the UI can subscribe once.
    public let levels: AsyncStream<Float>

    public private(set) var isCapturing = false

    public init() {
        (levels, levelContinuation) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Allocates the audio graph so the next `start` is fast.
    ///
    /// Does nothing until the microphone has been granted, both because there
    /// is nothing useful to warm up before then and because an unauthorized
    /// input node reports a zero-rate format.
    public func prewarm() {
        guard !isCapturing, MicrophoneAuthorization.isAuthorized else { return }
        // Referencing the input node attaches it. `prepare()` raises on a graph
        // that has no nodes at all.
        _ = engine.inputNode
        engine.prepare()
    }

    /// Begins capture, converting to `target` when the engine needs a specific
    /// format. The returned stream finishes when `stop()` is called.
    public func start(convertingTo target: AVAudioFormat?) throws -> AsyncStream<CapturedAudio> {
        if isCapturing { stop() }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.unsupportedFormat
        }

        var converter: BufferConverter?
        if let target, target != inputFormat {
            guard let made = BufferConverter(from: inputFormat, to: target) else {
                throw CaptureError.unsupportedFormat
            }
            converter = made
        }

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .unbounded)
        audioContinuation = continuation

        // Everything the tap touches is captured by value here: the closure runs
        // on a realtime audio thread and must not reach back into this actor.
        let levelSink = levelContinuation
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            levelSink.yield(AudioLevel.normalized(from: buffer))

            if let converter {
                guard let converted = converter.convert(buffer) else { return }
                continuation.yield(CapturedAudio(buffer: converted))
            } else if let copy = buffer.copyingContents() {
                continuation.yield(CapturedAudio(buffer: copy))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            audioContinuation = nil
            throw error
        }

        isCapturing = true
        logger.debug("Capture started at \(inputFormat.sampleRate, privacy: .public) Hz")
        return stream
    }

    public func stop() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        isCapturing = false
        levelContinuation.yield(0)

        // Stay warm so the next utterance starts without rebuilding the graph.
        engine.prepare()
    }
}

/// Microphone permission, which macOS and iOS both gate behind TCC.
public enum MicrophoneAuthorization {
    public static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }

    /// Requests access, returning whether it is now granted.
    public static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}

extension AVAudioPCMBuffer {
    /// A private copy of this buffer's samples.
    ///
    /// `AVAudioEngine` reuses the buffer it hands to a tap, so anything that
    /// outlives the callback has to own its own storage.
    func copyingContents() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength

        let channels = Int(format.channelCount)
        let frames = Int(frameLength)

        if let source = floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }

        if let source = int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }

        return nil
    }
}
