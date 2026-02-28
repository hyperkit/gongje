import Foundation
import SwiftUI

struct SettingsManager {
    @AppStorage("selectedModel") static var selectedModelRaw: String = WhisperModel.systemRecommended.rawValue
    @AppStorage("showOverlay") static var showOverlay: Bool = true
    @AppStorage("preserveClipboard") static var preserveClipboard: Bool = true
    @AppStorage("autoPaste") static var autoPaste: Bool = false
    @AppStorage("voiceOverAnnouncements") static var voiceOverAnnouncements: Bool = true

    static var selectedModel: WhisperModel {
        get { WhisperModel(rawValue: selectedModelRaw) ?? .systemRecommended }
        set { selectedModelRaw = newValue.rawValue }
    }

    // LLM Generation
    @AppStorage("llmTemperature")          static var llmTemperature: Double = 0.0
    @AppStorage("llmTopP")                 static var llmTopP: Double = 1.0
    @AppStorage("llmRepetitionPenalty")    static var llmRepetitionPenalty: Double = 1.0
    @AppStorage("llmMaxTokensCap")         static var llmMaxTokensCap: Int = 96
    @AppStorage("llmMaxTokensBuffer")      static var llmMaxTokensBuffer: Int = 24
    @AppStorage("llmDebounceMs")           static var llmDebounceMs: Int = 300

    // Prompt Templates
    @AppStorage("llmSystemPrompt")         static var llmSystemPrompt: String = LLMService.defaultSystemPrompt
    @AppStorage("llmUserPromptTemplate")   static var llmUserPromptTemplate: String = LLMService.defaultUserPromptTemplate

    // Noise Reduction
    @AppStorage("noiseReductionEnabled")  static var noiseReductionEnabled: Bool = true
    @AppStorage("noiseReductionStrength") static var noiseReductionStrength: Double = 0.5

    // Whisper Decoding
    @AppStorage("whisperLanguage")                       static var whisperLanguage: String = "yue"
    @AppStorage("whisperTemperature")                    static var whisperTemperature: Double = 0.0
    @AppStorage("whisperCompressionRatioThreshold")      static var whisperCompressionRatioThreshold: Double = 2.2
    @AppStorage("whisperLogProbThreshold")               static var whisperLogProbThreshold: Double = -0.8
    @AppStorage("whisperFirstTokenLogProbThreshold")     static var whisperFirstTokenLogProbThreshold: Double = -1.2
    @AppStorage("whisperNoSpeechThreshold")              static var whisperNoSpeechThreshold: Double = 0.5

    // Whisper Streaming
    @AppStorage("whisperRequiredSegments") static var whisperRequiredSegments: Int = 2
    @AppStorage("whisperSilenceThreshold") static var whisperSilenceThreshold: Double = 0.3
}
