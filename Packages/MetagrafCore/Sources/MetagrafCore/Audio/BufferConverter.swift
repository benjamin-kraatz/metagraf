import AVFoundation

/// Converts microphone buffers into the sample rate and channel layout a
/// transcription engine asks for.
///
/// The microphone typically delivers 48 kHz stereo float while speech models
/// want 16 kHz mono, so a conversion sits between capture and every engine.
///
/// Marked `@unchecked Sendable` so it can live inside the capture tap: the tap
/// is invoked serially on one audio thread, which is the only place `convert`
/// is ever called.
final class BufferConverter: @unchecked Sendable {
    let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        converter.primeMethod = .none
        self.converter = converter
        self.outputFormat = output
    }

    /// Converts one buffer. Returns `nil` when the converter produced no frames,
    /// which happens legitimately while a downsampler fills its internal window.
    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        // Round up and add headroom; the resampler can emit slightly more frames
        // than the naive ratio suggests, and an undersized buffer errors out.
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64

        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
