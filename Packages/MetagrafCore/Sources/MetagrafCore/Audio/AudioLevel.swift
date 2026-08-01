import AVFoundation
import Foundation

enum AudioLevel {
    /// Loudness of a buffer as a 0…1 value suitable for driving a meter.
    ///
    /// Speech sits far below full scale, so raw RMS barely moves a bar graph.
    /// Mapping decibels across a −50…0 dB window spends the visible range on
    /// the levels a voice actually produces.
    static func normalized(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        let frameCount = Int(buffer.frameLength)
        let samples = channels[0]

        var sumOfSquares: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sumOfSquares += sample * sample
        }

        let meanSquare = sumOfSquares / Float(frameCount)
        guard meanSquare > 0 else { return 0 }

        let decibels = 10 * log10f(meanSquare)
        let floor: Float = -50
        guard decibels > floor else { return 0 }

        return min(1, (decibels - floor) / -floor)
    }
}
