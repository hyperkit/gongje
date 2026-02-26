import Accelerate
import Foundation

struct FrequencyAnalyzer {
    let speechBands: Int
    let flankBands: Int

    private let fftSetup: vDSP_DFT_Setup
    private let fftLength: Int

    init(speechBands: Int = 40, flankBands: Int = 12, fftLength: Int = 2048) {
        self.speechBands = speechBands
        self.flankBands = flankBands
        self.fftLength = fftLength
        self.fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftLength),
            .FORWARD
        )!
    }

    /// Returns only the speech frequency bands (85–4000 Hz).
    func analyze(_ samples: ContiguousArray<Float>) -> [Float] {
        guard samples.count >= fftLength else {
            return [Float](repeating: 0, count: speechBands)
        }

        let startIndex = samples.count - fftLength
        var window = [Float](repeating: 0, count: fftLength)
        for i in 0..<fftLength {
            window[i] = samples[startIndex + i]
        }

        var hannWindow = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))
        vDSP_vmul(window, 1, hannWindow, 1, &window, 1, vDSP_Length(fftLength))

        var realInput = window
        var imagInput = [Float](repeating: 0, count: fftLength)
        var realOutput = [Float](repeating: 0, count: fftLength)
        var imagOutput = [Float](repeating: 0, count: fftLength)

        vDSP_DFT_Execute(fftSetup, &realInput, &imagInput, &realOutput, &imagOutput)

        let halfLength = fftLength / 2
        var magnitudes = [Float](repeating: 0, count: halfLength)
        for i in 0..<halfLength {
            magnitudes[i] = sqrtf(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }

        // Speech frequencies only: 85 Hz – 4000 Hz
        let sampleRate: Float = 16000
        let binHz = sampleRate / Float(fftLength)
        let minBin = Int(85.0 / binHz)
        let maxBin = min(Int(4000.0 / binHz), halfLength)
        let binSpan = maxBin - minBin

        var bands = [Float](repeating: 0, count: speechBands)
        for b in 0..<speechBands {
            let lowFrac = Float(b) / Float(speechBands)
            let highFrac = Float(b + 1) / Float(speechBands)
            let lowBin = minBin + Int(powf(lowFrac, 2) * Float(binSpan))
            let highBin = max(minBin + Int(powf(highFrac, 2) * Float(binSpan)), lowBin + 1)
            let clampedHigh = min(highBin, maxBin)

            var sum: Float = 0
            for i in lowBin..<clampedHigh {
                sum += magnitudes[i]
            }
            bands[b] = sum / Float(clampedHigh - lowBin)
        }

        let noiseFloor: Float = -30
        let range: Float = 60 // wider range → 50% quieter bars

        for b in 0..<speechBands {
            let db = 20 * log10f(max(bands[b], 1e-10))
            bands[b] = max((db - noiseFloor) / range, 0)
        }

        return bands
    }
}
