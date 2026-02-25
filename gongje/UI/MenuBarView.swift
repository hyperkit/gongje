import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow

            Divider()

            if appState.isRecording {
                Button("Stop Recording") {
                    appState.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
            } else {
                Button("Start Recording") {
                    appState.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.modelLoadState.isInProgress)
            }

            Divider()

            modelStatusRow

            Button("Unload Models") {
                appState.unloadAllModels()
            }
            .disabled(
                appState.isRecording
                    || appState.modelLoadState.isInProgress
                    || appState.llmLoadState.isInProgress
                    || (appState.modelLoadState == .notLoaded && appState.llmLoadState == .notLoaded)
            )

            Divider()

            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(width: 240)
    }

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
        }
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        switch appState.modelLoadState {
        case .loaded: return .green
        case .error: return .red
        case .notLoaded, .downloading, .loading: return .orange
        }
    }

    private var statusText: LocalizedStringKey {
        if appState.isRecording { return "Recording..." }
        switch appState.modelLoadState {
        case .notLoaded: return "Model Not Loaded"
        case .downloading: return "Downloading Model..."
        case .loading: return "Loading Model..."
        case .loaded: return "Ready"
        case .error: return "Error"
        }
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        modelStateLabel("Whisper", state: appState.modelLoadState, name: appState.selectedModel.displayName)

        if appState.llmEnabled {
            modelStateLabel("LLM", state: appState.llmLoadState, name: appState.selectedLLMModel.displayName)
        }
    }

    @ViewBuilder
    private func modelStateLabel(_ label: String, state: ModelLoadState, name: String) -> some View {
        switch state {
        case .notLoaded:
            Text("\(label): Not loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let progress):
            Text("\(label) \(textProgressBar(progress)) \(Int(progress * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        case .loading:
            Text("\(label): Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded:
            Text("\(label): \(name)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let msg):
            Text("\(label): \(msg)")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func textProgressBar(_ progress: Double, width: Int = 15) -> String {
        let filled = Int(progress * Double(width))
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }
}
