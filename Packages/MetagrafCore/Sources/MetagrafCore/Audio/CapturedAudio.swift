import AVFoundation

/// A microphone buffer handed off from the realtime audio thread.
///
/// `AVAudioPCMBuffer` is not `Sendable`. Each buffer wrapped here is freshly
/// allocated inside the capture tap and never touched again by the audio
/// thread, so handing ownership to another isolation domain is safe even though
/// the compiler cannot prove it.
public struct CapturedAudio: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    /// Duration of this buffer in seconds.
    public var duration: TimeInterval {
        guard buffer.format.sampleRate > 0 else { return 0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }
}
