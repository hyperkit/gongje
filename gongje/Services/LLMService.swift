import Foundation
import Hub
import MLXLMCommon
import MLXLLM

actor LLMService {
    private var container: ModelContainer?
    private var currentModel: LLMModel?
    private var generationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private static var downloadBase: URL { TranscriptionService.downloadBase }

    func loadModel(_ model: LLMModel) async throws {
        let loaded: ModelContainer
        let base = Self.downloadBase

        // Check if model already exists locally
        if let localDir = model.resolveDirectory(base: base) {
            await MainActor.run { appState.llmLoadState = .loading }
            print("[Gongje] Loading local LLM from: \(localDir.path)")
            loaded = try await loadModelContainer(directory: localDir)
        } else if let hfID = model.modelRepo {
            // Download from HuggingFace into the shared download base
            await MainActor.run { appState.llmLoadState = .downloading(progress: 0) }
            let hub = HubApi(downloadBase: base)
            loaded = try await loadModelContainer(hub: hub, id: hfID) { [weak self] progress in
                guard let self else { return }
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    self.appState.llmLoadState = .downloading(progress: fraction)
                }
            }
        } else {
            throw LLMError.modelNotFound(model.displayName, expectedPath: "")
        }

        container = loaded
        currentModel = model
        await MainActor.run { appState.llmLoadState = .loaded }
        print("[Gongje] LLM loaded: \(model.rawValue)")
    }

    enum LLMError: LocalizedError {
        case modelNotFound(String, expectedPath: String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name, let path):
                String(localized: "Local model not found: \(name). Place model files in: \(path)")
            }
        }
    }

    func correctText(_ rawText: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(SettingsManager.llmDebounceMs))
            } catch { return }
            await self.startCorrection(rawText)
        }
    }

    func cancelAll() {
        debounceTask?.cancel()
        debounceTask = nil
        generationTask?.cancel()
        generationTask = nil
    }

    func unloadModel() async {
        cancelAll()
        container = nil
        currentModel = nil
        await MainActor.run {
            appState.llmLoadState = .notLoaded
            appState.correctedText = ""
        }
        print("[Gongje] LLM unloaded")
    }

    // MARK: - Defaults (exposed for SettingsManager)

    static let defaultSystemPrompt = """
        修正廣東話語音轉文字嘅同音錯字。

        規則：
        1. 只改同音/近音錯字，唔確定就保留原文。
        2. 保持廣東話繁體字，唔好轉普通話（保留「嘅」唔好改做「的」）。
        3. 保留標點、換行、數字、英文、專有名詞原樣不變。
        4. 保持字數一致，只輸出修正後文字，無需解釋。

        例：
        香港自開化後 世界各國人士分支疊來 市場繁榮 百貨充電 -> 香港自開埠後 世界各國人士紛至沓來 市場繁榮 百貨充闐
        不過而家要揾到一部打掃電話嘅電話題 -> 不過而家要揾到一部打到電話嘅電話亭
        """

    static let defaultUserPromptTemplate = """
        [TEXT]
        {text}
        [/TEXT]
        """

    // MARK: - Private

    private static let blockedOutputMarkers = [
        "<system-reminder>",
        "</system-reminder>",
        "your operational mode has changed",
        "operational mode",
        "read-only mode",
        "plan to build",
        "<|im_start|>",
        "<|im_end|>",
    ]

    private static let blockedPersonaMarkers = [
        "我係一個",
        "我是一個",
        "我嘅任務",
        "我的任務",
        "文字校正助手",
        "我會根據",
    ]

    private func startCorrection(_ rawText: String) {
        generationTask?.cancel()
        
        print("[Gongje] Raw text to correct by LLM: \(rawText)")

        guard let container else { return }

        let sanitizedRawText = Self.sanitizeInputText(rawText)
        guard !sanitizedRawText.isEmpty else {
            Task { @MainActor [weak self] in
                self?.appState.correctedText = ""
            }
            return
        }

        if Self.containsBlockedMarker(sanitizedRawText) {
            Task { @MainActor [weak self] in
                self?.appState.correctedText = sanitizedRawText
            }
            return
        }

        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let input = UserInput(
                    chat: [
                        .system(SettingsManager.llmSystemPrompt),
                        .user(Self.buildUserPrompt(for: sanitizedRawText)),
                    ]
                )
                let lmInput = try await container.prepare(input: input)

                let estimatedInputTokens = max(8, sanitizedRawText.count)
                let maxCorrectionTokens = min(
                    SettingsManager.llmMaxTokensCap,
                    estimatedInputTokens + SettingsManager.llmMaxTokensBuffer
                )

                let params = GenerateParameters(
                    maxTokens: maxCorrectionTokens,
                    temperature: Float(SettingsManager.llmTemperature),
                    topP: Float(SettingsManager.llmTopP),
                    repetitionPenalty: Float(SettingsManager.llmRepetitionPenalty)
                )

                var accumulated = ""
                let stream = try await container.generate(input: lmInput, parameters: params)
                for await generation in stream {
                    if Task.isCancelled { return }
                    switch generation {
                    case .chunk(let text):
                        accumulated += text
                    case .info:
                        break
                    case .toolCall:
                        break
                    }
                }

                let selectedWhisperModel = await MainActor.run { self.appState.selectedModel }
                let finalized = Self.sanitizeModelOutput(
                    accumulated,
                    fallback: sanitizedRawText,
                    sourceModel: selectedWhisperModel
                )
                await MainActor.run { [weak self] in
                    self?.appState.correctedText = finalized
                }
            } catch {
                if !Task.isCancelled {
                    print("[Gongje] LLM correction error: \(error)")
                }
            }
        }
    }

    private static func sanitizeInputText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = removeSystemReminderBlock(cleaned)
        cleaned = removeControlBlocks(cleaned)
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
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeModelOutput(
        _ output: String,
        fallback: String,
        sourceModel: WhisperModel
    ) -> String {
        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = removeSystemReminderBlock(cleaned)

        if cleaned.contains("<") || cleaned.contains(">") {
            print("[Gongje] LLM output rejected: contains angle brackets")
            return fallback
        }
        if containsBlockedMarker(cleaned) {
            print("[Gongje] LLM output rejected: blocked marker detected")
            return fallback
        }
        if containsPersonaLeak(cleaned) {
            print("[Gongje] LLM output rejected: persona leak detected")
            return fallback
        }

        if cleaned.hasPrefix("修正後：") {
            cleaned = String(cleaned.dropFirst("修正後：".count))
        } else if cleaned.hasPrefix("校正後：") {
            cleaned = String(cleaned.dropFirst("校正後：".count))
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            print("[Gongje] LLM output rejected: empty after sanitization")
            return fallback
        }
        guard isReasonableCorrection(input: fallback, output: cleaned, sourceModel: sourceModel) else {
            print("[Gongje] LLM output rejected: correction drift too large : \(output) vs \(fallback)")
            return fallback
        }
        return cleaned
    }

    private static func removeSystemReminderBlock(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<system-reminder>[\s\S]*?</system-reminder>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func removeControlBlocks(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?is)your operational mode has changed[\s\S]*?utilize your arsenal of tools as needed\."#,
            with: "",
            options: .regularExpression
        )
    }

    private static func containsBlockedMarker(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return blockedOutputMarkers.contains(where: { lowercased.contains($0.lowercased()) })
    }

    private static func containsPersonaLeak(_ text: String) -> Bool {
        blockedPersonaMarkers.contains(where: { text.contains($0) })
    }

    private static func buildUserPrompt(for rawText: String) -> String {
        SettingsManager.llmUserPromptTemplate.replacingOccurrences(of: "{text}", with: rawText)
    }

    private static func isReasonableCorrection(
        input: String,
        output: String,
        sourceModel: WhisperModel
    ) -> Bool {
        if input == output { return true }

        let inputLines = input.split(separator: "\n", omittingEmptySubsequences: false).count
        let outputLines = output.split(separator: "\n", omittingEmptySubsequences: false).count
        if inputLines != outputLines { return false }

        let inputChars = Array(input)
        let outputChars = Array(output)
        if inputChars.isEmpty || outputChars.isEmpty { return false }

        let maxLengthGap = max(2, inputChars.count / 8)
        if abs(inputChars.count - outputChars.count) > maxLengthGap { return false }

        let distance = levenshteinDistance(inputChars, outputChars)
        let baseMaxDistance = Double(inputChars.count) / 3.0
        let maxDistance = max(4, Int(baseMaxDistance * sourceModel.llmCorrectionDistanceScale))
        return distance <= maxDistance
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        for (i, aChar) in a.enumerated() {
            var current = Array(repeating: 0, count: b.count + 1)
            current[0] = i + 1

            for (j, bChar) in b.enumerated() {
                let cost = aChar == bChar ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
            }

            previous = current
        }

        return previous[b.count]
    }
}
