import Accelerate
import AVFoundation
import CoreML
import Foundation
import WhisperKit

/// A wrapper around WhisperKit's `AudioProcessor` that applies lightweight noise
/// reduction (high-pass biquad + spectral gating) to each audio buffer before it
/// reaches the transcriber. Both filters use Apple's Accelerate framework (vDSP),
/// which runs on the AMX coprocessor on Apple Silicon at near-zero CPU/GPU cost.
final class NoiseSuppressingAudioProcessor: NSObject, AudioProcessing {
    private let wrapped: any AudioProcessing

    // MARK: - AudioProcessing state

    private(set) var audioSamples: ContiguousArray<Float> = []
    private var audioEnergy: [(rel: Float, avg: Float, max: Float, min: Float)] = []
    var relativeEnergy: [Float] { audioEnergy.map { $0.rel } }
    var relativeEnergyWindow: Int = 20

    // MARK: - Biquad high-pass filter (85 Hz cutoff)

    private var biquadState: [Float] = [0, 0, 0, 0]
    private let biquadCoeffs: [Float]

    // MARK: - Spectral gating

    private let fftSetup: vDSP_DFT_Setup
    private let ifftSetup: vDSP_DFT_Setup
    private let fftLength = 2048
    private var noiseProfile: [Float]?
    private var noiseProfileAccum: [Float]?
    private var noiseProfileFrames: Int = 0
    private let noiseLearnFrames = 5

    // Overlap-add state
    private var overlapBuffer: [Float]

    /// Spectral gate aggressiveness — mapped from `SettingsManager.noiseReductionStrength`.
    /// 0.0 = minimal filtering, 1.0 = aggressive.
    var strength: Double = 0.5

    // MARK: - Init

    init(wrapping processor: any AudioProcessing) {
        self.wrapped = processor
        self.overlapBuffer = [Float](repeating: 0, count: fftLength / 2)

        // Compute biquad coefficients for a second-order Butterworth high-pass at 85 Hz / 16 kHz
        let sampleRate: Float = 16000
        let cutoff: Float = 85
        let w0 = 2.0 * Float.pi * cutoff / sampleRate
        let cosW0 = cosf(w0)
        let sinW0 = sinf(w0)
        let alpha = sinW0 / (2.0 * sqrtf(2.0)) // Q = sqrt(2)/2 for Butterworth

        let a0 = 1.0 + alpha
        // vDSP_deq22 coefficients: [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
        let b0 = ((1.0 + cosW0) / 2.0) / a0
        let b1 = (-(1.0 + cosW0)) / a0
        let b2 = ((1.0 + cosW0) / 2.0) / a0
        let a1 = (-2.0 * cosW0) / a0
        let a2 = (1.0 - alpha) / a0
        self.biquadCoeffs = [b0, b1, b2, a1, a2]

        guard let fft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftLength), .FORWARD),
              let ifft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftLength), .INVERSE) else {
            fatalError("[Gongje] Failed to create DFT setup for noise suppression")
        }
        self.fftSetup = fft
        self.ifftSetup = ifft

        super.init()
    }

    // MARK: - AudioProcessing conformance (delegated)

    static func loadAudio(
        fromPath audioFilePath: String,
        channelMode: ChannelMode,
        startTime: Double?,
        endTime: Double?,
        maxReadFrameSize: AVAudioFrameCount?
    ) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(
            fromPath: audioFilePath,
            channelMode: channelMode,
            startTime: startTime,
            endTime: endTime,
            maxReadFrameSize: maxReadFrameSize
        )
    }

    static func loadAudio(
        at audioPaths: [String],
        channelMode: ChannelMode
    ) async -> [Result<[Float], Swift.Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }

    static func padOrTrimAudio(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int,
        saveSegment: Bool
    ) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: saveSegment
        )
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        if keep <= 0 {
            audioSamples.removeAll()
            audioEnergy.removeAll()
        } else {
            let samplesToRemove = max(audioSamples.count - keep, 0)
            if samplesToRemove > 0 {
                audioSamples.removeFirst(samplesToRemove)
            }
        }
        // Also purge the wrapped processor
        wrapped.purgeAudioSamples(keepingLast: keep)
    }

    func startRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws {
        // Reset state
        audioSamples = []
        audioEnergy = []
        noiseProfile = nil
        noiseProfileAccum = nil
        noiseProfileFrames = 0
        biquadState = [0, 0, 0, 0]
        overlapBuffer = [Float](repeating: 0, count: fftLength / 2)
        strength = SettingsManager.noiseReductionStrength

        // Start the real processor with our intercepting callback
        try wrapped.startRecordingLive(inputDeviceID: inputDeviceID) { [weak self] buffer in
            guard let self else { return }
            let filtered = self.filterBuffer(buffer)
            self.appendFiltered(filtered)
            callback?(filtered)
        }
    }

    func startStreamingRecordingLive(
        inputDeviceID: DeviceID?
    ) -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        // Not used by AudioStreamTranscriber in this project, delegate to wrapped
        wrapped.startStreamingRecordingLive(inputDeviceID: inputDeviceID)
    }

    func pauseRecording() {
        wrapped.pauseRecording()
    }

    func stopRecording() {
        wrapped.stopRecording()
    }

    func resumeRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws {
        strength = SettingsManager.noiseReductionStrength
        try wrapped.resumeRecordingLive(inputDeviceID: inputDeviceID) { [weak self] buffer in
            guard let self else { return }
            let filtered = self.filterBuffer(buffer)
            self.appendFiltered(filtered)
            callback?(filtered)
        }
    }

    func padOrTrim(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int
    ) -> (any AudioProcessorOutputType)? {
        Self.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: false
        )
    }

    // MARK: - Filtering

    private func appendFiltered(_ buffer: [Float]) {
        audioSamples.append(contentsOf: buffer)

        // Compute energy metrics (same as AudioProcessor.processBuffer)
        let minAvgEnergy = audioEnergy.suffix(relativeEnergyWindow)
            .reduce(Float.infinity) { min($0, $1.avg) }
        let rel = Self.calculateRelativeEnergy(of: buffer, relativeTo: minAvgEnergy)
        let signal = Self.calculateEnergy(of: buffer)
        audioEnergy.append((rel, signal.avg, signal.max, signal.min))
    }

    func filterBuffer(_ buffer: [Float]) -> [Float] {
        var result = buffer

        // 1. High-pass biquad filter
        applyHighPass(&result)

        // 2. Spectral gating (only if buffer is large enough)
        if result.count >= fftLength {
            applySpectralGate(&result)
        } else if result.count > 0 {
            // For short buffers, still learn noise profile by zero-padding
            learnNoiseFromShortBuffer(result)
        }

        return result
    }

    // MARK: - High-pass biquad via vDSP_deq22

    private func applyHighPass(_ buffer: inout [Float]) {
        guard buffer.count > 2 else { return }

        // vDSP_deq22 processes in-place with a 5-coefficient filter
        // Input needs 2 extra samples prepended (state from previous call)
        var extended = [Float](repeating: 0, count: buffer.count + 2)
        extended[0] = biquadState[0]
        extended[1] = biquadState[1]
        for i in 0..<buffer.count {
            extended[i + 2] = buffer[i]
        }

        var output = [Float](repeating: 0, count: buffer.count + 2)
        output[0] = biquadState[2]
        output[1] = biquadState[3]

        var coeffs = biquadCoeffs
        vDSP_deq22(&extended, 1, &coeffs, &output, 1, vDSP_Length(buffer.count))

        // Save state for next call
        biquadState[0] = extended[buffer.count]
        biquadState[1] = extended[buffer.count + 1]
        biquadState[2] = output[buffer.count]
        biquadState[3] = output[buffer.count + 1]

        // Copy filtered output back
        for i in 0..<buffer.count {
            buffer[i] = output[i + 2]
        }
    }

    // MARK: - Spectral gating

    private func learnNoiseFromShortBuffer(_ buffer: [Float]) {
        guard noiseProfileFrames < noiseLearnFrames else { return }

        // Zero-pad to fftLength and learn
        var padded = [Float](repeating: 0, count: fftLength)
        let count = min(buffer.count, fftLength)
        for i in 0..<count { padded[i] = buffer[i] }

        let magnitudes = computeMagnitudes(padded)
        accumulateNoiseProfile(magnitudes)
    }

    private func applySpectralGate(_ buffer: inout [Float]) {
        let halfLen = fftLength / 2

        // Process the last fftLength samples of the buffer
        let processStart = max(buffer.count - fftLength, 0)
        var segment = [Float](repeating: 0, count: fftLength)
        let segmentLen = buffer.count - processStart
        for i in 0..<segmentLen {
            segment[i] = buffer[processStart + i]
        }

        // Apply Hann window
        var hannWindow = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))
        vDSP_vmul(segment, 1, hannWindow, 1, &segment, 1, vDSP_Length(fftLength))

        // Forward FFT
        var realIn = segment
        var imagIn = [Float](repeating: 0, count: fftLength)
        var realOut = [Float](repeating: 0, count: fftLength)
        var imagOut = [Float](repeating: 0, count: fftLength)

        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)

        // Compute magnitudes
        var magnitudes = [Float](repeating: 0, count: halfLen)
        for i in 0..<halfLen {
            magnitudes[i] = sqrtf(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        // Noise profile learning phase
        if noiseProfileFrames < noiseLearnFrames {
            accumulateNoiseProfile(magnitudes)
            // During learning, pass audio through unmodified (minus high-pass already applied)
            return
        }

        guard let profile = noiseProfile else { return }

        // Spectral gating: attenuate bins dominated by noise
        // threshold scales with strength: higher strength = more aggressive gating
        let threshold = Float(1.0 + strength * 2.0) // range: 1.0 – 3.0
        let attenuation = Float(max(0.02, 0.15 - strength * 0.13)) // range: 0.15 – 0.02

        for i in 0..<halfLen {
            if magnitudes[i] < profile[i] * threshold {
                // Soft attenuation — don't zero out completely to avoid artifacts
                realOut[i] *= attenuation
                imagOut[i] *= attenuation
                // Mirror for negative frequencies
                if i > 0 && i < halfLen {
                    realOut[fftLength - i] *= attenuation
                    imagOut[fftLength - i] *= attenuation
                }
            }
        }

        // Inverse FFT
        var ifftReal = [Float](repeating: 0, count: fftLength)
        var ifftImag = [Float](repeating: 0, count: fftLength)
        vDSP_DFT_Execute(ifftSetup, &realOut, &imagOut, &ifftReal, &ifftImag)

        // Normalize IFFT output (vDSP DFT doesn't normalize)
        var scale = Float(1.0 / Float(fftLength))
        vDSP_vsmul(ifftReal, 1, &scale, &ifftReal, 1, vDSP_Length(fftLength))

        // Overlap-add for smooth output
        let hopSize = halfLen
        for i in 0..<hopSize {
            ifftReal[i] += overlapBuffer[i]
        }

        // Save second half for next overlap
        overlapBuffer = Array(ifftReal[hopSize..<fftLength])

        // Write filtered samples back into buffer
        for i in 0..<min(segmentLen, hopSize) {
            buffer[processStart + i] = ifftReal[i]
        }
    }

    private func computeMagnitudes(_ segment: [Float]) -> [Float] {
        let halfLen = fftLength / 2
        var hannWindow = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))

        var windowed = [Float](repeating: 0, count: fftLength)
        vDSP_vmul(segment, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftLength))

        var realIn = windowed
        var imagIn = [Float](repeating: 0, count: fftLength)
        var realOut = [Float](repeating: 0, count: fftLength)
        var imagOut = [Float](repeating: 0, count: fftLength)

        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0, count: halfLen)
        for i in 0..<halfLen {
            magnitudes[i] = sqrtf(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }
        return magnitudes
    }

    private func accumulateNoiseProfile(_ magnitudes: [Float]) {
        let halfLen = fftLength / 2
        if noiseProfileAccum == nil {
            noiseProfileAccum = [Float](repeating: 0, count: halfLen)
        }

        for i in 0..<halfLen {
            noiseProfileAccum![i] += magnitudes[i]
        }
        noiseProfileFrames += 1

        if noiseProfileFrames >= noiseLearnFrames {
            // Finalize: average the accumulated magnitudes
            noiseProfile = noiseProfileAccum!.map { $0 / Float(noiseProfileFrames) }
            noiseProfileAccum = nil
            print("[Gongje] Noise profile learned (\(noiseProfileFrames) frames)")
        }
    }

    // MARK: - Energy calculation (mirrors AudioProcessor)

    private static func calculateRelativeEnergy(of buffer: [Float], relativeTo minEnergy: Float) -> Float {
        let energy = calculateEnergy(of: buffer)
        let refEnergy = max(minEnergy, 1e-10)
        return energy.avg / refEnergy
    }

    private static func calculateEnergy(of buffer: [Float]) -> (avg: Float, max: Float, min: Float) {
        guard !buffer.isEmpty else { return (0, 0, 0) }
        var sum: Float = 0
        var maxVal: Float = -.greatestFiniteMagnitude
        var minVal: Float = .greatestFiniteMagnitude
        for sample in buffer {
            let abs = abs(sample)
            sum += abs
            if abs > maxVal { maxVal = abs }
            if abs < minVal { minVal = abs }
        }
        return (sum / Float(buffer.count), maxVal, minVal)
    }
}
