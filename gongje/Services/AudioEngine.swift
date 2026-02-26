import Foundation
import WhisperKit

enum AudioEngine {
    static func requestPermission() async -> Bool {
        await AudioProcessor.requestRecordPermission()
    }
}
