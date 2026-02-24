import AppKit
import Foundation
import SwiftUI

enum ModelLoadState: Equatable {
    case notLoaded
    case downloading(progress: Double)
    case loading
    case loaded
    case error(String)

    var isInProgress: Bool {
        switch self {
        case .downloading, .loading: true
        default: false
        }
    }
}

@Observable
final class AppState {
    var isRecording = false
    var confirmedText = ""
    var hypothesisText = ""
    var modelLoadState: ModelLoadState = .notLoaded
    var downloadProgress: Double = 0
    var selectedModel: WhisperModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }

    // MARK: - LLM

    var llmEnabled: Bool {
        didSet {
            UserDefaults.standard.set(llmEnabled, forKey: "llmEnabled")
            if !llmEnabled {
                correctedText = ""
                Task { await llmService?.unloadModel() }
            }
        }
    }
    var selectedLLMModel: LLMModel {
        didSet {
            UserDefaults.standard.set(selectedLLMModel.rawValue, forKey: "selectedLLMModel")
        }
    }
    var llmLoadState: ModelLoadState = .notLoaded
    var correctedText = ""
    var audioEnergy: [Float] = []

    private var transcriptionService: TranscriptionService?
    private(set) var llmService: LLMService?

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedModel")
        selectedModel = saved.flatMap(WhisperModel.init(rawValue:)) ?? .systemRecommended

        llmEnabled = UserDefaults.standard.bool(forKey: "llmEnabled")
        let savedLLM = UserDefaults.standard.string(forKey: "selectedLLMModel")
        selectedLLMModel = savedLLM.flatMap(LLMModel.init(rawValue:)) ?? .qwen25_15b
    }

    func setTranscriptionService(_ service: TranscriptionService) {
        transcriptionService = service
    }

    func setLLMService(_ service: LLMService) {
        llmService = service
    }

    @MainActor
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @MainActor
    private func startRecording() {
        confirmedText = ""
        hypothesisText = ""
        isRecording = true

        if modelLoadState != .loaded {
            Task {
                await loadModel()
                guard modelLoadState == .loaded else {
                    isRecording = false
                    return
                }
                await transcriptionService?.startStreaming()

                if llmEnabled && llmLoadState != .loaded {
                    await loadLLMModel()
                }
            }
        } else {
            Task {
                await transcriptionService?.startStreaming()
            }
        }
    }

    @MainActor
    private func stopRecording() {
        isRecording = false
        Task {
            await transcriptionService?.stopStreaming()
            NSSound(named: "Pop")?.play()
        }
    }

    @MainActor
    func unloadAllModels() {
        if isRecording {
            stopRecording()
        }
        Task {
            await transcriptionService?.unloadModel()
        }
        modelLoadState = .notLoaded

        Task {
            await llmService?.unloadModel()
        }
        llmLoadState = .notLoaded

        print("[Gongje] All models unloaded")
    }

    @MainActor
    func loadModel() async {
        guard transcriptionService != nil else {
            print("[Gongje] Cannot load model: transcription service not set")
            modelLoadState = .error(String(localized: "Transcription service not initialized"))
            return
        }
        modelLoadState = .loading
        do {
            try await transcriptionService?.loadModel(selectedModel)
            modelLoadState = .loaded
        } catch {
            print("[Gongje] Model load failed: \(error)")
            modelLoadState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func loadLLMModel() async {
        guard llmEnabled else {
            llmLoadState = .notLoaded
            return
        }
        guard let llmService else {
            print("[Gongje] Cannot load LLM: service not set")
            llmLoadState = .error(String(localized: "LLM service not initialized"))
            return
        }
        llmLoadState = .loading
        do {
            try await llmService.loadModel(selectedLLMModel)
            guard llmEnabled else {
                await llmService.unloadModel()
                return
            }
            llmLoadState = .loaded
        } catch {
            print("[Gongje] LLM load failed: \(error)")
            llmLoadState = .error(error.localizedDescription)
        }
    }
}
