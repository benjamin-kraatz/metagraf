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
        case noInputDevice
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied:
                // iOS refuses microphone access to app extensions outright, so
                // in one there is no permission the user could grant to fix it.
                // Saying "allow microphone access" would send them looking for
                // a switch that does not exist.
                Metagraf.isRunningInExtension
                    ? String(
                        localized: "iOS doesn’t let keyboards use the microphone.",
                        bundle: .main
                    )
                    : String(localized: "Metagraf needs microphone access to hear you.", bundle: .main)
            case .noInputDevice:
                String(localized: "No microphone is available right now.", bundle: .main)
            case .unsupportedFormat:
                String(localized: "The selected input device produced an unusable audio format.", bundle: .main)
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
        #if os(macOS)
        // Referencing the input node attaches it. `prepare()` raises on a graph
        // that has no nodes at all.
        _ = engine.inputNode
        engine.prepare()
        #else
        // Not on iOS: reaching for the input node before a recording session is
        // active makes AVAudioEngine cache a zero-rate input format, and it
        // keeps that stale format even once the session comes up properly.
        #endif
    }

    /// Begins capture, converting to `target` when the engine needs a specific
    /// format. The returned stream finishes when `stop()` is called.
    public func start(convertingTo target: AVAudioFormat?) throws -> AsyncStream<CapturedAudio> {
        if isCapturing { stop() }
        try activateAudioSession()

        try requireInputRoute()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            // A zero-rate input node nearly always means there is no microphone
            // route rather than a genuinely odd format, so say the useful thing.
            logger.error(
                """
                Input node unusable: \(inputFormat.sampleRate, privacy: .public) Hz, \
                \(inputFormat.channelCount, privacy: .public) ch, \
                authorized=\(MicrophoneAuthorization.isAuthorized, privacy: .public)
                """
            )
            throw MicrophoneAuthorization.isAuthorized
                ? CaptureError.unsupportedFormat
                : CaptureError.microphoneAccessDenied
        }

        // Bound as a `let` so the tap closure captures it by value; capturing a
        // `var` across the concurrency boundary would be a race.
        let converter: BufferConverter?
        if let target, target != inputFormat {
            guard let made = BufferConverter(from: inputFormat, to: target) else {
                throw CaptureError.unsupportedFormat
            }
            converter = made
        } else {
            converter = nil
        }

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .unbounded)
        audioContinuation = continuation

        // Everything the tap touches is captured by value here: the closure runs
        // on a realtime audio thread and must not reach back into this actor.
        //
        // `@Sendable` is load-bearing. `AVAudioNodeTapBlock` is an Objective-C
        // block with no sendability annotation, so inside this `@MainActor`
        // type Swift would otherwise infer the closure as main-actor-isolated
        // and emit an isolation check — which traps the moment AVAudioEngine
        // invokes it from its realtime thread.
        let levelSink = levelContinuation
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
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
        deactivateAudioSession()
    }

    /// Fails early when the system has no microphone to give us.
    ///
    /// In an app extension this is the common case and the confusing one: the
    /// audio session activates happily, but the route is empty because the
    /// microphone was never granted to the *containing* app. An extension
    /// cannot show that prompt itself, so the message has to send the user to
    /// the app rather than to a Settings switch that will not help.
    private func requireInputRoute() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let hasRoute = !session.currentRoute.inputs.isEmpty

        guard session.isInputAvailable, hasRoute else {
            logger.error(
                """
                No input route: inputAvailable=\(session.isInputAvailable, privacy: .public), \
                routes=\(session.currentRoute.inputs.count, privacy: .public), \
                permission=\(String(describing: AVAudioApplication.shared.recordPermission), privacy: .public)
                """
            )
            throw AVAudioApplication.shared.recordPermission == .granted
                ? CaptureError.noInputDevice
                : CaptureError.microphoneAccessDenied
        }
        #endif
    }

    /// iOS requires an active, recording-capable audio session before the input
    /// node produces anything; macOS has no equivalent step.
    private func activateAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // `.measurement` turns off the system's own signal processing, which is
        // tuned for calls and works against speech recognition.
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        // Handing the session back lets whatever was playing before resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
