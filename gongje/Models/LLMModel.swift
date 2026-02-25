import Foundation

enum LLMModel: String, CaseIterable, Identifiable, Codable {
    case qwen3_17b = "Qwen_Qwen3-1.7B-MLX-4bit"
    case qwen3_4b = "Qwen_Qwen3-4B-MLX-4bit"
    case qwen3_8b = "Qwen_Qwen3-8B-MLX-4bit"
    case qwen2Cantonese7b = "hyperkit_Qwen2-Cantonese-7B-Instruct-mlx"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen3_17b: String(localized: "Qwen 3 1.7B (~1.2 GB)")
        case .qwen3_4b: String(localized: "Qwen 3 4B (~2.5 GB)")
        case .qwen3_8b: String(localized: "Qwen 3 8B (~5 GB)")
        case .qwen2Cantonese7b: String(localized: "Qwen 2 Cantonese 7B (~4 GB)")
        }
    }

    var shortDescription: String {
        switch self {
        case .qwen3_17b:
            return String(localized: "Generic Qwen 3 model which is lightweight and fastest; suitable for basic typo correction.")
        case .qwen3_4b:
            return String(localized: "Generic Qwen 3 model which has recommended balance of quality, speed, and memory usage.")
        case .qwen3_8b:
            return String(localized: "Generic Qwen 3 model which has stronger correction quality with higher memory cost.")
        case .qwen2Cantonese7b:
            return String(localized: "Cantonese-focused Qwen 2 model which has stronger correction quality with higher memory cost.")
        }
    }

    var huggingFaceURL: URL? {
        let repo = originalModelRepo ?? modelRepo
        guard let repo else { return nil }
        return URL(string: "https://huggingface.co/\(repo)")
    }

    var minimumRAMGB: Int {
        switch self {
        case .qwen3_17b: 4
        case .qwen3_4b: 8
        case .qwen3_8b: 16
        case .qwen2Cantonese7b: 16
        }
    }

    /// The HuggingFace repo containing the MLX model for downloading.
    var modelRepo: String? {
        switch self {
        case .qwen3_17b: "Qwen/Qwen3-1.7B-MLX-4bit"
        case .qwen3_4b: "Qwen/Qwen3-4B-MLX-4bit"
        case .qwen3_8b: "Qwen/Qwen3-8B-MLX-4bit"
        case .qwen2Cantonese7b: "hyperkit/Qwen2-Cantonese-7B-Instruct-mlx"
        }
    }

    /// The original upstream model repo before any MLX conversion.
    var originalModelRepo: String? {
        switch self {
        case .qwen3_17b: "Qwen/Qwen3-1.7B"
        case .qwen3_4b: "Qwen/Qwen3-4B"
        case .qwen3_8b: "Qwen/Qwen3-8B"
        case .qwen2Cantonese7b: "lordjia/Qwen2-Cantonese-7B-Instruct"
        }
    }

    /// Resolve model directory under the shared download base.
    /// Uses the HubApi cache structure: `downloadBase/models/{org}/{repo}/`
    func resolveDirectory(base: URL) -> URL? {
        guard let repo = modelRepo else { return nil }
        let modelDir = base.appending(path: "models").appending(path: repo)
        let fm = FileManager.default
        if fm.fileExists(atPath: modelDir.appending(path: "config.json").path) {
            return modelDir
        }
        return nil
    }
}
