import SwiftUI

struct TranscriptionOverlayView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showWaveform") private var showWaveform = WaveformDefaults.defaultEnabled

    private var hasText: Bool {
        !appState.confirmedText.isEmpty || !appState.hypothesisText.isEmpty || !appState.correctedText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(appState.isRecording ? 1 : 0)
                Text("Gongje")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if case .error(let msg) = appState.modelLoadState {
                Text(msg)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if case .downloading(let progress) = appState.modelLoadState {
                Text("Downloading model... \(Int(progress * 100))%")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            } else if case .loading = appState.modelLoadState {
                Text("Loading model...")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            } else if hasText {
                Text(displayText)
                    .font(.system(size: 16))
                    .lineLimit(5)
                    .truncationMode(.head)
            } else if appState.isRecording {
                Text("Listening...")
                    .font(.system(size: 16))
                    .foregroundStyle(.gray)
            }
        }
        .padding(12)
        .frame(minWidth: 300, maxWidth: 500, alignment: .leading)
        .background {
            if appState.isRecording && showWaveform {
                WaveformView(energy: appState.audioEnergy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if !appState.correctedText.isEmpty {
            return appState.correctedText
        }
        let full = appState.confirmedText + appState.hypothesisText
        if !full.isEmpty {
            return full
        }
        if appState.isRecording {
            return String(localized: "Listening...")
        }
        return "Gongje"
    }

    private var displayText: AttributedString {
        let corrected = appState.correctedText
        let confirmed = appState.confirmedText
        let hypothesis = appState.hypothesisText

        let llmEnabled = appState.llmEnabled

        // If LLM-corrected text is available, show it in white (confident)
        if !corrected.isEmpty {
            let text = truncateTail(corrected, maxLength: 200)
            var result = AttributedString(text)
            result.foregroundColor = .white
            return result
        }

        let full = confirmed + hypothesis

        // Limit display to last 200 characters to keep overlay readable
        let maxDisplay = 200
        let trimmedConfirmed: String
        let trimmedHypothesis: String

        if full.count > maxDisplay {
            let startIndex = full.index(full.endIndex, offsetBy: -maxDisplay)
            let trimmed = String(full[startIndex...])
            if hypothesis.count >= trimmed.count {
                trimmedConfirmed = ""
                trimmedHypothesis = trimmed
            } else {
                trimmedConfirmed = String(trimmed.dropLast(hypothesis.count))
                trimmedHypothesis = hypothesis
            }
        } else {
            trimmedConfirmed = confirmed
            trimmedHypothesis = hypothesis
        }

        var result = AttributedString(trimmedConfirmed)
        result.foregroundColor = .white

        // When LLM is disabled, show hypothesis in white (no correction pending).
        // When LLM is enabled, show hypothesis in gray to indicate it's awaiting correction.
        var hyp = AttributedString(trimmedHypothesis)
        hyp.foregroundColor = llmEnabled ? .gray : .white

        result.append(hyp)
        return result
    }

    private func truncateTail(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxLength)
        return String(text[start...])
    }
}
