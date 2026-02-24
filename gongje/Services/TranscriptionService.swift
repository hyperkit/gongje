import AppKit
import Foundation
import Hub
import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var currentModel: WhisperModel?
    private var streamTranscriber: AudioStreamTranscriber?

    private var injectedLength = 0
    private var fullText = ""
    private var previousFullText = ""
    private var deferredFlushText = "" // text from stream resets, waiting to be sent
    private var flushTask: Task<Void, Never>?

    private let appState: AppState
    private let llmService: LLMService?
    private let frequencyAnalyzer = FrequencyAnalyzer()

    init(appState: AppState, llmService: LLMService? = nil) {
        self.appState = appState
        self.llmService = llmService
    }

    static let downloadBase: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "gongje/huggingface")
    }()

    func loadModel(_ model: WhisperModel) async throws {
        let modelFolder: URL

        if let localFolder = Self.existingModelFolder(for: model) {
            print("[Gongje] Found local model: \(localFolder.path)")
            modelFolder = localFolder
        } else {
            print("[Gongje] Downloading model: \(model.rawValue)...")
            await MainActor.run { appState.modelLoadState = .downloading(progress: 0) }

            let progressCallback: ((Progress) -> Void) = { [weak self] progress in
                guard let self else { return }
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    self.appState.modelLoadState = .downloading(progress: fraction)
                }
            }

            if model.isFlatRepo, let repo = model.modelRepo {
                // Flat repos have model files at root — use HubApi.snapshot directly
                let hubApi = HubApi(downloadBase: Self.downloadBase)
                modelFolder = try await hubApi.snapshot(
                    from: repo,
                    progressHandler: progressCallback
                )
            } else if let repo = model.modelRepo {
                modelFolder = try await WhisperKit.download(
                    variant: model.rawValue,
                    downloadBase: Self.downloadBase,
                    from: repo,
                    progressCallback: progressCallback
                )
            } else {
                modelFolder = try await WhisperKit.download(
                    variant: model.rawValue,
                    downloadBase: Self.downloadBase,
                    progressCallback: progressCallback
                )
            }
        }

        print("[Gongje] Loading model from: \(modelFolder.path)...")
        await MainActor.run { appState.modelLoadState = .loading }

        let config = WhisperKitConfig(
            model: model.rawValue,
            modelFolder: modelFolder.path,
            verbose: true,
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        currentModel = model
        print("[Gongje] Model loaded successfully: \(model.rawValue)")
    }

    func unloadModel() {
        whisperKit = nil
        currentModel = nil
        print("[Gongje] Whisper model unloaded")
    }

    /// Check if a model's CoreML files already exist locally.
    /// Searches the HuggingFace cache structure used by WhisperKit's `HubApi`:
    ///   `downloadBase/models/{repo_org}/{repo_name}/{variant}/`
    /// and a flat layout for manually placed models:
    ///   `downloadBase/models/{variant}/`
    private static func existingModelFolder(for model: WhisperModel) -> URL? {
        let fm = FileManager.default
        let modelsBase = downloadBase.appending(path: "models")

        var candidates: [URL] = []

        // HuggingFace cache path: models/{org}/{repo}/{variant}
        if let repo = model.modelRepo {
            let parts = repo.split(separator: "/")
            if parts.count == 2 {
                let repoBase = modelsBase
                    .appending(path: String(parts[0]))
                    .appending(path: String(parts[1]))
                // Variant subfolder layout
                candidates.append(repoBase.appending(path: model.rawValue))
                // Flat repo layout (files at repo root)
                if model.isFlatRepo {
                    candidates.append(repoBase)
                }
            }
        }

        // Default WhisperKit repo path: models/argmaxinc/whisperkit-coreml/{variant}
        candidates.append(
            modelsBase
                .appending(path: "argmaxinc")
                .appending(path: "whisperkit-coreml")
                .appending(path: model.rawValue)
        )

        // Flat layout: models/{variant}
        candidates.append(modelsBase.appending(path: model.rawValue))

        for folder in candidates {
            let encoder = folder.appending(path: "AudioEncoder.mlmodelc")
            let decoder = folder.appending(path: "TextDecoder.mlmodelc")
            if fm.fileExists(atPath: encoder.path) && fm.fileExists(atPath: decoder.path) {
                return folder
            }
        }

        return nil
    }

    func startStreaming() async {
        guard let whisperKit, let tokenizer = whisperKit.tokenizer else {
            print("[Gongje] Cannot start streaming: model not loaded or tokenizer unavailable")
            await MainActor.run { appState.isRecording = false }
            return
        }

        // Play sound before audio hardware is reconfigured for recording.
        await MainActor.run { NSSound(named: "Pop")?.play() }
        try? await Task.sleep(for: .milliseconds(150))

        injectedLength = 0
        fullText = ""
        previousFullText = ""
        deferredFlushText = ""
        flushTask?.cancel()
        flushTask = nil
        await MainActor.run { appState.correctedText = "" }

        let options = DecodingOptions(
            task: .transcribe,
            language: "yue",
            temperature: 0.0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: false,
            compressionRatioThreshold: 2.2,
            logProbThreshold: -0.8,
            firstTokenLogProbThreshold: -1.2,
            noSpeechThreshold: 0.5,
            chunkingStrategy: .vad
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: 2,
            silenceThreshold: 0.3,
            compressionCheckWindow: 60,
            useVAD: true,
            stateChangeCallback: { [weak self] oldState, newState in
                guard let self else { return }
                Task { await self.handleStateChange(newState: newState) }
            }
        )

        streamTranscriber = transcriber

        do {
            try await transcriber.startStreamTranscription()
        } catch {
            print("[Gongje] Streaming transcription error: \(error)")
            await MainActor.run { appState.isRecording = false }
        }
    }

    func stopStreaming() async {
        flushTask?.cancel()
        flushTask = nil

        await streamTranscriber?.stopStreamTranscription()
        streamTranscriber = nil

        // Combine any deferred text with current pending text
        var allPending = deferredFlushText
        let pending = pendingText
        if !pending.isEmpty {
            if !allPending.isEmpty { allPending += " " }
            allPending += pending
        }

        // Prefer LLM-corrected text if available
        let corrected = await MainActor.run { appState.correctedText }
        let finalText = corrected.isEmpty ? sanitizeText(allPending) : corrected

        if !finalText.isEmpty && isValidTranscription(finalText) {
            await MainActor.run {
                TextOutputService.injectText(finalText)
            }
        }

        await llmService?.cancelAll()

        fullText = ""
        previousFullText = ""
        injectedLength = 0
        deferredFlushText = ""

        // Purge audio buffer after the transcriber is stopped so the next
        // session starts with a clean audioProcessor state.
        whisperKit?.audioProcessor.purgeAudioSamples(keepingLast: 0)

        await MainActor.run {
            appState.confirmedText = ""
            appState.hypothesisText = ""
            appState.correctedText = ""
            appState.audioEnergy = []
        }
    }

    // MARK: - Private

    private var pendingText: String {
        guard fullText.count > injectedLength else { return "" }
        let start = fullText.index(fullText.startIndex, offsetBy: injectedLength)
        return String(fullText[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All text waiting to be sent — deferred flush text plus current pending,
    /// with model-specific noise markers stripped.
    private var displayText: String {
        var result = deferredFlushText
        let pending = pendingText
        if !pending.isEmpty {
            if !result.isEmpty { result += " " }
            result += pending
        }
        return sanitizeText(result)
    }

    /// Strip model-specific noise markers (e.g. `%nz`) from transcription output.
    private func sanitizeText(_ text: String) -> String {
        var cleaned = text
        if let marker = currentModel?.noiseMarker {
            cleaned = cleaned.replacingOccurrences(of: marker, with: "")
        }
        cleaned = cleaned.replacingOccurrences(
            of: #"<system-reminder>[\s\S]*?</system-reminder>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"</?system-reminder>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?is)your operational mode has changed[\s\S]*?utilize your arsenal of tools as needed\."#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestLLMCorrection(_ text: String) {
        guard let llmService, appState.llmEnabled else { return }
        Task { await llmService.correctText(text) }
    }

    /// Filter out Whisper hallucinations — meta-commentary like "[speaking Cantonese]",
    /// "(music)", repeated filler, known phantom phrases from silence, etc.
    private func isValidTranscription(_ text: String) -> Bool {
        let trimmed = sanitizeText(text)
        if trimmed.isEmpty { return false }

        // Reject text wrapped in brackets — hallucination markers
        if trimmed.contains("[") || trimmed.contains("]")
            || trimmed.contains("(") || trimmed.contains(")") {
            return false
        }

        if trimmed.contains("<") || trimmed.contains(">") {
            return false
        }

        let lowered = trimmed.lowercased()
        if lowered.contains("system-reminder")
            || lowered.contains("operational mode")
            || lowered.contains("read-only mode") {
            return false
        }

        // Model-specific hallucination phrases (exact match)
        if let model = currentModel {
            for pattern in model.hallucinationPatterns {
                if lowered == pattern.lowercased() {
                    return false
                }
            }
        }

        return true
    }

    private func handleStateChange(newState: AudioStreamTranscriber.State) {
        // Compute frequency spectrum from raw audio for visualizer
        if let audioProcessor = whisperKit?.audioProcessor {
            let bands = frequencyAnalyzer.analyze(audioProcessor.audioSamples)
            Task { @MainActor in
                appState.audioEnergy = bands
            }
        }

        let allSegments = newState.confirmedSegments + newState.unconfirmedSegments
        var currentFullText = allSegments.map(\.text).joined()

        if currentFullText.isEmpty
            && !newState.currentText.isEmpty
            && newState.currentText != "Waiting for speech..." {
            currentFullText = newState.currentText
        }

        let textChanged = currentFullText != previousFullText
        let priorFullText = fullText
        let hadPending = priorFullText.count > injectedLength
        previousFullText = currentFullText
        fullText = currentFullText

        // Stream reset: VAD detected a pause and cleared segments.
        // Don't flush yet — accumulate in deferredFlushText and start a
        // timer. If new speech arrives, the timer is cancelled and the
        // deferred text stays buffered. If silence persists, the timer
        // fires and sends everything.
        if textChanged && currentFullText.isEmpty && hadPending {
            let startOffset = min(injectedLength, priorFullText.count)
            let prevStart = priorFullText.index(priorFullText.startIndex, offsetBy: startOffset)
            let remainingText = String(priorFullText[prevStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Reset tracking state — the old segments are gone
            injectedLength = 0
            fullText = ""
            previousFullText = ""

            if !remainingText.isEmpty && isValidTranscription(remainingText) {
                if !deferredFlushText.isEmpty {
                    deferredFlushText += remainingText
                } else {
                    deferredFlushText = remainingText
                }
                print("[Gongje] VAD pause — deferred: \(remainingText) (total: \(deferredFlushText))")
            } else if !remainingText.isEmpty {
                print("[Gongje] Filtered hallucination: \(remainingText)")
            }

            // Start/reset the flush timer. Fires after 3s of no new text.
            startFlushTimer()

            // Update overlay with all accumulated text (hide hallucinations)
            let display = displayText
            let validDisplay = isValidTranscription(display) ? display : ""
            Task { @MainActor in
                appState.confirmedText = ""
                appState.hypothesisText = validDisplay
            }
            if !validDisplay.isEmpty {
                requestLLMCorrection(validDisplay)
            }
            return
        }

        // New text arrived from a new decode cycle — cancel the flush timer
        // since the user is still speaking. The new decode already includes
        // the previously deferred text (same audio re-decoded), so clear it.
        // Must happen before computing displayText to avoid duplication.
        if textChanged && !currentFullText.isEmpty {
            flushTask?.cancel()
            flushTask = nil
            deferredFlushText = ""
        }

        let display = displayText

        // Don't show hallucinated text in the overlay
        let validDisplay = isValidTranscription(display) ? display : ""

        // Update overlay
        Task { @MainActor in
            appState.confirmedText = ""
            appState.hypothesisText = validDisplay
        }

        if textChanged && !validDisplay.isEmpty {
            requestLLMCorrection(validDisplay)
        }
    }

    private func startFlushTimer() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch { return }
            await self.flushDeferred()
        }
    }

    private func flushDeferred() {
        let rawText = displayText
        guard !rawText.isEmpty && isValidTranscription(rawText) else {
            deferredFlushText = ""
            return
        }

        print("[Gongje] Silence flush: \(rawText)")
        deferredFlushText = ""
        injectedLength = fullText.count

        Task { @MainActor in
            let corrected = appState.correctedText
            let finalText = corrected.isEmpty ? rawText : corrected
            TextOutputService.injectText(finalText)
            appState.confirmedText = ""
            appState.hypothesisText = ""
            appState.correctedText = ""
        }

        Task { await llmService?.cancelAll() }
    }
}
