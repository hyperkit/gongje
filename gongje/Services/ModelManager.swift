import Foundation
import WhisperKit

@Observable
final class ModelManager {
    var availableModels: [String] = []
    var downloadProgress: Double = 0
    var isDownloading = false
    var errorMessage: String?

    func fetchAvailableModels() async {
        do {
            let models = try await WhisperKit.fetchAvailableModels()
            await MainActor.run {
                self.availableModels = models.sorted()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func downloadModel(_ model: WhisperModel) async throws -> URL {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        let folder = try await WhisperKit.download(
            variant: model.rawValue,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
        )

        return folder
    }

    func recommendedModels() -> ModelSupport {
        WhisperKit.recommendedModels()
    }
}
