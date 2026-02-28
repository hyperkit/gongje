import Combine
import SwiftUI

struct WaveformView: View {
    var energy: [Float]

    private let flankBars = 12
    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 2

    @State private var displayEnergy: [Float] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let totalBars = flankBars + displayEnergy.count + flankBars
            guard totalBars > 0 else { return }

            let barWidth = (size.width - barSpacing * CGFloat(totalBars - 1)) / CGFloat(totalBars)
            let step = barWidth + barSpacing
            let maxAmplitude = size.height * 0.4
            let cornerRadius = min(barWidth / 2, 1.5)
            let color: GraphicsContext.Shading = .color(.white.opacity(0.35))

            for i in 0..<flankBars {
                let x = CGFloat(i) * step
                let rect = CGRect(x: x, y: midY - minBarHeight / 2,
                                  width: barWidth, height: minBarHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: color)
            }

            let centerOffset = CGFloat(flankBars) * step
            let fadeCount = 6 // number of bars to fade on each edge
            let count = displayEnergy.count
            for i in 0..<count {
                // Smooth fade at edges: ease-in from 0→1 over fadeCount bars
                let fade: CGFloat
                if i < fadeCount {
                    let t = CGFloat(i) / CGFloat(fadeCount)
                    fade = t * t // ease-in
                } else if i >= count - fadeCount {
                    let t = CGFloat(count - 1 - i) / CGFloat(fadeCount)
                    fade = t * t
                } else {
                    fade = 1
                }

                let val = CGFloat(max(min(displayEnergy[i], 1), 0)) * fade
                let barHeight = max(val * maxAmplitude * 2, minBarHeight)
                let x = centerOffset + CGFloat(i) * step
                let rect = CGRect(x: x, y: midY - barHeight / 2,
                                  width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: color)
            }

            let rightOffset = CGFloat(flankBars + displayEnergy.count) * step
            for i in 0..<flankBars {
                let x = rightOffset + CGFloat(i) * step
                let rect = CGRect(x: x, y: midY - minBarHeight / 2,
                                  width: barWidth, height: minBarHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: color)
            }
        }
        .onAppear { if !reduceMotion { DisplayLink.start() } }
        .onChange(of: energy, initial: true) { _, newValue in
            if reduceMotion || displayEnergy.count != newValue.count {
                displayEnergy = newValue
            }
        }
        .accessibilityHidden(true)
        .onReceive(DisplayLink.publisher) {
            guard !reduceMotion else {
                displayEnergy = energy
                return
            }
            guard displayEnergy.count == energy.count else {
                displayEnergy = energy
                return
            }
            let smoothing: Float = 0.25
            for i in 0..<displayEnergy.count {
                displayEnergy[i] += (energy[i] - displayEnergy[i]) * smoothing
            }
        }
    }
}

// MARK: - CVDisplayLink → Combine publisher (60 fps)

private var displayLinkFrameToggle = false

private enum DisplayLink {
    static let publisher = PassthroughSubject<Void, Never>()

    private static var link: CVDisplayLink?

    static func start() {
        guard link == nil else { return }
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, _ in
            // Flip half the refresh rate (e.g. reduce from 60fps to 30fps)
            displayLinkFrameToggle.toggle()
            guard displayLinkFrameToggle else { return kCVReturnSuccess }
            DispatchQueue.main.async { DisplayLink.publisher.send() }
            return kCVReturnSuccess
        }, nil)
        CVDisplayLinkStart(link)
    }
}
