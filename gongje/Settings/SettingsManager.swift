import Foundation
import SwiftUI

struct SettingsManager {
    @AppStorage("selectedModel") static var selectedModelRaw: String = WhisperModel.systemRecommended.rawValue
    @AppStorage("showOverlay") static var showOverlay: Bool = true
    @AppStorage("preserveClipboard") static var preserveClipboard: Bool = true

    static var selectedModel: WhisperModel {
        get { WhisperModel(rawValue: selectedModelRaw) ?? .systemRecommended }
        set { selectedModelRaw = newValue.rawValue }
    }
}
