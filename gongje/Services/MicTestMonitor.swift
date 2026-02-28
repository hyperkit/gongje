import AVFoundation
import Foundation

/// Lightweight audio capture for the setup wizard mic test.
/// Uses AVAudioEngine directly (no WhisperKit dependency) and feeds
/// downsampled samples to FrequencyAnalyzer for waveform visualization.
@Observable
final class MicTestMonitor {
    private(set) var bands: [Float] = []
    private(set) var isRunning = false

    private var engine: AVAudioEngine?
    private let analyzer = FrequencyAnalyzer()
    private var samples = ContiguousArray<Float>()

    func start() {
        guard !isRunning else { return }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard hardwareFormat.sampleRate > 0 else { return }

        let decimationFactor = max(1, Int(hardwareFormat.sampleRate / 16000))

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let ptr = channelData[0]

            for i in stride(from: 0, to: frameCount, by: decimationFactor) {
                self.samples.append(ptr[i])
            }

            let maxSamples = 4096
            if self.samples.count > maxSamples {
                self.samples.removeFirst(self.samples.count - maxSamples)
            }

            let newBands = self.analyzer.analyze(self.samples)
            DispatchQueue.main.async {
                self.bands = newBands
            }
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("[MicTest] Failed to start audio engine: \(error)")
            self.engine = nil
        }
    }

    func stop() {
        guard isRunning else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        samples.removeAll()
    }

    deinit {
        if isRunning {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
    }
}
