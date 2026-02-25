import Foundation

enum LLMModel: String, CaseIterable, Identifiable, Codable {
    case qwen25_05b = "mlx-community_Qwen2.5-0.5B-Instruct-4bit"
    case qwen25_15b = "mlx-community_Qwen2.5-1.5B-Instruct-4bit"
    case qwen25_3b = "mlx-community_Qwen2.5-3B-Instruct-4bit"
    case qwen2Cantonese7b = "hyperkit_Qwen2-Cantonese-7B-Instruct-mlx"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen25_05b: String(localized: "Qwen 2.5 0.5B (~400 MB)")
        case .qwen25_15b: String(localized: "Qwen 2.5 1.5B (~870 MB)")
        case .qwen25_3b: String(localized: "Qwen 2.5 3B (~1.8 GB)")
        case .qwen2Cantonese7b: String(localized: "Cantonese 7B (~4 GB)")
        }
    }

    var shortDescription: String {
        switch self {
        case .qwen25_05b:
            return String(localized: "Lightweight and fastest; suitable for basic typo correction.")
        case .qwen25_15b:
            return String(localized: "Recommended balance of quality, speed, and memory usage.")
        case .qwen25_3b:
            return String(localized: "Stronger correction quality with higher memory cost.")
        case .qwen2Cantonese7b:
            return String(localized: "Best Cantonese-focused correction quality.")
        }
    }

    var huggingFaceURL: URL? {
        let repo = originalModelRepo ?? modelRepo
        guard let repo else { return nil }
        return URL(string: "https://huggingface.co/\(repo)")
    }

    var minimumRAMGB: Int {
        switch self {
        case .qwen25_05b: 4
        case .qwen25_15b: 8
        case .qwen25_3b: 16
        case .qwen2Cantonese7b: 16
        }
    }

    /// The HuggingFace repo containing the MLX model for downloading.
    var modelRepo: String? {
        switch self {
        case .qwen25_05b: "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        case .qwen25_15b: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        case .qwen25_3b: "mlx-community/Qwen2.5-3B-Instruct-4bit"
        case .qwen2Cantonese7b: "hyperkit/Qwen2-Cantonese-7B-Instruct-mlx"
        }
    }

    /// The original upstream model repo before any MLX conversion.
    var originalModelRepo: String? {
        switch self {
        case .qwen25_05b: "Qwen/Qwen2.5-0.5B-Instruct"
        case .qwen25_15b: "Qwen/Qwen2.5-1.5B-Instruct"
        case .qwen25_3b: "Qwen/Qwen2.5-3B-Instruct"
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
