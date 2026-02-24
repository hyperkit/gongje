import Foundation

enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    
    enum LanguageStyleGroup: String, CaseIterable, Identifiable {
        case writtenChinese
        case spokenCantonese

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .writtenChinese:
                /// Models which supporting written Chinese such as 那個, 他們, 怎樣, 不是, 的
                return String(localized: "Whisper models support written Chinese")
            case .spokenCantonese:
                /// Models which support spoken Cantonese 嗰個, 佢哋, 點解, 唔係, 嘅
                return String(localized: "Whisper models support spoken Cantonese")
            }
        }
    }

    /// Open AI whisper models
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case largeV3 = "openai_whisper-large-v3"
    
    /// Other community whisper models that targets Cantonese
    case cantoneseSmall = "alvanlii_distil-whisper-small-cantonese"
    case cantoneseLargeV3Turbo = "JackyHoCL_whisper-large-v3-turbo-cantonese-yue-english"

    var id: String { rawValue }

    var languageStyleGroup: LanguageStyleGroup {
        switch self {
        case .small, .medium, .largeV3:
            return .writtenChinese
        case .cantoneseSmall, .cantoneseLargeV3Turbo:
            return .spokenCantonese
        }
    }

    var displayName: String {
        switch self {
        case .small: String(localized: "Small (~500 MB)")
        case .medium: String(localized: "Medium (~1.5 GB)")
        case .largeV3: String(localized: "Large V3 (~3 GB)")
        case .cantoneseSmall: String(localized: "Cantonese Small (~500 MB)")
        case .cantoneseLargeV3Turbo: String(localized: "Cantonese Large V3 Turbo (~1.5 GB)")
        }
    }

    var shortDescription: String {
        switch self {
        case .small:
            return String(localized: "Good default for better accuracy with moderate resource use. Runs via WhisperKit CoreML conversion of OpenAI Whisper Small.")
        case .medium:
            return String(localized: "Higher accuracy, better for mixed accents and longer speech. Runs via WhisperKit CoreML conversion of OpenAI Whisper Medium.")
        case .largeV3:
            return String(localized: "Best OpenAI accuracy, but requires more memory and load time. Runs via WhisperKit CoreML conversion of OpenAI Whisper Large V3.")
        case .cantoneseSmall:
            return String(localized: "Fine-tuned for spoken Cantonese with efficient size. Runs via WhisperKit CoreML conversion of AlvanLii's Distil Whisper Small.")
        case .cantoneseLargeV3Turbo:
            return String(localized: "Higher spoken Cantonese/English quality with better accuracy and supporting Mandarin. Runs via WhisperKit CoreML conversion of JackyHoCL's Whisper Large V3 Turbo.")
        }
    }

    var huggingFaceURL: URL? {
        let repo = originalModelRepo ?? modelRepo
        guard let repo else { return nil }
        return URL(string: "https://huggingface.co/\(repo)")
    }

    var minimumRAMGB: Int {
        switch self {
        case .small, .cantoneseSmall: 8
        case .medium, .largeV3, .cantoneseLargeV3Turbo: 16
        }
    }

    /// Whether this model requires a custom HuggingFace repo (non-OpenAI models).
    var isCustom: Bool {
        switch self {
        case .cantoneseSmall, .cantoneseLargeV3Turbo: true
        default: false
        }
    }

    /// The HuggingFace repo containing CoreML-converted models for custom models.
    var modelRepo: String? {
        switch self {
        case .small, .medium, .largeV3:
            return "argmaxinc/whisperkit-coreml"
        case .cantoneseSmall:
            return "hyperkit/distil-whisper-small-cantonese-coreml"
        case .cantoneseLargeV3Turbo:
            return "hyperkit/whisper-large-v3-turbo-cantonese-yue-english-coreml"
        }
    }

    /// The original upstream model repo before any CoreML conversion.
    var originalModelRepo: String? {
        switch self {
        case .small:
            return "openai/whisper-small"
        case .medium:
            return "openai/whisper-medium"
        case .largeV3:
            return "openai/whisper-large-v3"
        case .cantoneseSmall:
            return "alvanlii/distil-whisper-small-cantonese"
        case .cantoneseLargeV3Turbo:
            return "JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english"
        }
    }

    /// Whether model files are at the repo root (flat) rather than inside a variant subfolder.
    /// Flat repos can't use `WhisperKit.download` and need direct HubApi snapshot download.
    var isFlatRepo: Bool {
        switch self {
        case .cantoneseSmall, .cantoneseLargeV3Turbo: true
        default: false
        }
    }

    /// The noise marker token used by models with noise detection.
    var noiseMarker: String? {
        switch self {
        default: nil
        }
    }

    /// Known hallucination phrases this model emits on silence/noise, these are usually because of training from video subtitles
    var hallucinationPatterns: [String] {
        var patterns = Self.commonHallucinationPatterns
        switch self {
        case .cantoneseLargeV3Turbo:
            patterns += [
                "这种",
                "优优独播剧场——YoYo Television Series Exclusive",
                "这些",
                "这些人",
                "在这",
                "在北"
            ]
        case .cantoneseSmall:
            patterns += [
                "I'm going to make a hole in the middle of the box."
            ]
            break
        case .small, .medium, .largeV3:
            break
        }
        return patterns
    }

    /// Hallucination phrases common across all Whisper models,
    private static let commonHallucinationPatterns: [String] = [
    ]

    /// Scale used by LLM correction drift guard.
    /// Larger/fine-tuned Whisper models should need fewer edits from LLM.
    var llmCorrectionDistanceScale: Double {
        switch self {
        case .small, .cantoneseSmall:
            return 1.0
        case .medium:
            return 0.85
        case .largeV3, .cantoneseLargeV3Turbo:
            return 0.7
        }
    }

    static func recommended(forRAMGB ram: Int) -> WhisperModel {
        if ram < 16 { return .cantoneseSmall }
        return .cantoneseLargeV3Turbo
    }

    static func models(for group: LanguageStyleGroup) -> [WhisperModel] {
        allCases.filter { $0.languageStyleGroup == group }
    }

    static var systemRecommended: WhisperModel {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return recommended(forRAMGB: ramGB)
    }
}
