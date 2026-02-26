import SwiftUI

struct AdvancedSettingsView: View {
    // LLM Generation
    @AppStorage("llmTemperature")        private var llmTemperature: Double = 0.0
    @AppStorage("llmTopP")               private var llmTopP: Double = 1.0
    @AppStorage("llmRepetitionPenalty")  private var llmRepetitionPenalty: Double = 1.0
    @AppStorage("llmMaxTokensCap")       private var llmMaxTokensCap: Int = 96
    @AppStorage("llmMaxTokensBuffer")    private var llmMaxTokensBuffer: Int = 24
    @AppStorage("llmDebounceMs")         private var llmDebounceMs: Int = 300

    // Prompt Templates
    @AppStorage("llmSystemPrompt")          private var llmSystemPrompt: String = LLMService.defaultSystemPrompt
    @AppStorage("llmUserPromptTemplate")    private var llmUserPromptTemplate: String = LLMService.defaultUserPromptTemplate

    // Noise Reduction
    @AppStorage("noiseReductionEnabled")  private var noiseReductionEnabled: Bool = true
    @AppStorage("noiseReductionStrength") private var noiseReductionStrength: Double = 0.5

    // Whisper Decoding
    @AppStorage("whisperLanguage")                   private var whisperLanguage: String = "yue"
    @AppStorage("whisperTemperature")                private var whisperTemperature: Double = 0.0
    @AppStorage("whisperCompressionRatioThreshold")  private var whisperCompressionRatioThreshold: Double = 2.2
    @AppStorage("whisperLogProbThreshold")           private var whisperLogProbThreshold: Double = -0.8
    @AppStorage("whisperFirstTokenLogProbThreshold") private var whisperFirstTokenLogProbThreshold: Double = -1.2
    @AppStorage("whisperNoSpeechThreshold")          private var whisperNoSpeechThreshold: Double = 0.5

    // Whisper Streaming
    @AppStorage("whisperRequiredSegments") private var whisperRequiredSegments: Int = 2
    @AppStorage("whisperSilenceThreshold") private var whisperSilenceThreshold: Double = 0.3

    @AppStorage("appLanguageOverride") private var appLanguageOverride: String = "system"
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            noiseReductionSection
            whisperDecodingSection
            whisperStreamingSection
            llmGenerationSection
            promptTemplatesSection
            resetSection
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all advanced settings to defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All LLM and Whisper parameters, including prompt templates, will be restored to their original values.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var llmGenerationSection: some View {
        Section("LLM Generation") {
            doubleRow(
                title: "Temperature",
                caption: "Randomness of output. 0 = deterministic.",
                value: $llmTemperature,
                range: 0...1, step: 0.05, format: "%.2f"
            )
            doubleRow(
                title: "Top P",
                caption: "Nucleus sampling threshold.",
                value: $llmTopP,
                range: 0...1, step: 0.05, format: "%.2f"
            )
            doubleRow(
                title: "Repetition Penalty",
                caption: "Penalise repeated tokens. 1.0 = no penalty.",
                value: $llmRepetitionPenalty,
                range: 0.8...1.5, step: 0.05, format: "%.2f"
            )
            intRow(
                title: "Max Tokens Cap",
                caption: "Hard ceiling on generated tokens.",
                value: $llmMaxTokensCap,
                range: 32...512, step: 8
            )
            intRow(
                title: "Max Tokens Buffer",
                caption: "Added to input-length estimate for max tokens.",
                value: $llmMaxTokensBuffer,
                range: 8...128, step: 8
            )
            intRow(
                title: "Debounce (ms)",
                caption: "Delay before sending text to LLM while speaking.",
                value: $llmDebounceMs,
                range: 50...2000, step: 50
            )
        }
    }

    @ViewBuilder
    private var promptTemplatesSection: some View {
        Section("Prompt Templates") {
            LabeledContent {
                TextEditor(text: $llmSystemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 120)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Prompt")
                    Text("Instructs the LLM how to correct text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $llmUserPromptTemplate)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 70)
                    Text("Use {text} as a placeholder for the transcribed text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("User Prompt Template")
            }
        }
    }

    @ViewBuilder
    private var noiseReductionSection: some View {
        Section("Noise Reduction") {
            Toggle("Enable Noise Reduction", isOn: $noiseReductionEnabled)
            doubleRow(
                title: "Reduction Strength",
                caption: "How aggressively background noise is suppressed. Takes effect on next recording.",
                value: $noiseReductionStrength,
                range: 0...1, step: 0.05, format: "%.2f"
            )
            .disabled(!noiseReductionEnabled)
        }
    }

    @ViewBuilder
    private var whisperDecodingSection: some View {
        Section("Whisper Decoding") {
            LabeledContent {
                TextField("", text: $whisperLanguage)
                    .frame(maxWidth: 300)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper Language")
                    Text("BCP-47 language code passed to Whisper. (e.g. yue, zh, en)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            doubleRow(
                title: "Temperature",
                caption: "Decoding temperature. 0 = greedy.",
                value: $whisperTemperature,
                range: 0...1, step: 0.05, format: "%.2f"
            )
            doubleRow(
                title: "Compression Ratio Threshold",
                caption: "Segments above this ratio are discarded.",
                value: $whisperCompressionRatioThreshold,
                range: 1...4, step: 0.1, format: "%.1f"
            )
            doubleRow(
                title: "Log-Prob Threshold",
                caption: "Segments below this average log-prob are discarded.",
                value: $whisperLogProbThreshold,
                range: -3...0, step: 0.1, format: "%.1f"
            )
            doubleRow(
                title: "First-Token Log-Prob Threshold",
                caption: "Retry if first token log-prob is below this.",
                value: $whisperFirstTokenLogProbThreshold,
                range: -3...0, step: 0.1, format: "%.1f"
            )
            doubleRow(
                title: "No-Speech Threshold",
                caption: "Probability above which a segment is treated as silence.",
                value: $whisperNoSpeechThreshold,
                range: 0...1, step: 0.05, format: "%.2f"
            )
        }
    }

    @ViewBuilder
    private var whisperStreamingSection: some View {
        Section("Whisper Streaming") {
            intRow(
                title: "Required Segments",
                caption: "Confirmed segments needed before text is emitted.",
                value: $whisperRequiredSegments,
                range: 1...5, step: 1
            )
            doubleRow(
                title: "Silence Threshold",
                caption: "Audio energy level below which VAD treats audio as silence.",
                value: $whisperSilenceThreshold,
                range: 0...1, step: 0.05, format: "%.2f"
            )
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button("Reset All to Defaults", role: .destructive) {
                showResetConfirmation = true
            }
        }
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func doubleRow(
        title: String,
        caption: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step)
                    .frame(maxWidth: 180)
                TextField(
                    "",
                    value: value,
                    format: .number.precision(.fractionLength(0...2))
                )
                .frame(width: 52)
                .multilineTextAlignment(.trailing)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func intRow(
        title: String,
        caption: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .frame(maxWidth: 180)
                TextField("", value: value, format: .number)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Reset

    private func resetToDefaults() {
        noiseReductionEnabled = true
        noiseReductionStrength = 0.5
        llmTemperature = 0.0
        llmTopP = 1.0
        llmRepetitionPenalty = 1.0
        llmMaxTokensCap = 96
        llmMaxTokensBuffer = 24
        llmDebounceMs = 300
        let effectiveLang = LLMService.resolveEffectiveLanguage(for: appLanguageOverride)
        llmSystemPrompt = LLMService.defaultSystemPrompt(for: effectiveLang)
        llmUserPromptTemplate = LLMService.defaultUserPromptTemplate(for: effectiveLang)
        whisperLanguage = "yue"
        whisperTemperature = 0.0
        whisperCompressionRatioThreshold = 2.2
        whisperLogProbThreshold = -0.8
        whisperFirstTokenLogProbThreshold = -1.2
        whisperNoSpeechThreshold = 0.5
        whisperRequiredSegments = 2
        whisperSilenceThreshold = 0.3
    }
}
