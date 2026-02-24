import Foundation

enum LLMModel: String, CaseIterable, Identifiable, Codable {
    case qwen25_05b = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    case qwen25_15b = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    case qwen25_3b = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    case qwen2Cantonese7b = "local:Qwen2-Cantonese-7B-Instruct-mlx-4bit"

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
            return String(localized: "Best Cantonese-focused correction quality, requires local files.")
        }
    }

    var huggingFaceURL: URL? {
        guard let id = huggingFaceID else { return nil }
        return URL(string: "https://huggingface.co/\(id)")
    }

    var minimumRAMGB: Int {
        switch self {
        case .qwen25_05b: 4
        case .qwen25_15b: 8
        case .qwen25_3b: 16
        case .qwen2Cantonese7b: 16
        }
    }

    /// The HuggingFace model ID for remote models. `nil` for local-only models.
    var huggingFaceID: String? {
        switch self {
        case .qwen2Cantonese7b: nil
        default: rawValue
        }
    }

    /// The directory name used for local storage under the shared models folder.
    var localDirectoryName: String {
        switch self {
        case .qwen2Cantonese7b: "Qwen2-Cantonese-7B-Instruct-mlx-4bit"
        default: rawValue.replacingOccurrences(of: "/", with: "_")
        }
    }

    /// Resolve model directory under the shared download base.
    /// For local-only models, checks if the model files exist there.
    func resolveDirectory(base: URL) -> URL? {
        let modelDir = base.appending(path: "models").appending(path: localDirectoryName)
        let fm = FileManager.default
        if fm.fileExists(atPath: modelDir.appending(path: "config.json").path) {
            return modelDir
        }
        return nil
    }
}
