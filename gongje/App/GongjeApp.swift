import SwiftUI

struct GongjeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState
    @State private var transcriptionService: TranscriptionService
    @State private var didConfigure = false
    @AppStorage("setupCompleted") private var setupCompleted = false
    @AppStorage("appLanguageOverride") private var appLanguageOverride: String = "system"

    private var resolvedLocale: Locale {
        switch appLanguageOverride {
        case "system":
            let systemLang = UserDefaults.standard.string(forKey: "detectedSystemLanguage") ?? "en"
            return Locale(identifier: systemLang)
        default:
            return Locale(identifier: appLanguageOverride)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(\.locale, resolvedLocale)
        } label: {
            MenuBarIcon(appState: appState, setupCompleted: setupCompleted)
                .task {
                    guard setupCompleted, !didConfigure else { return }
                    didConfigure = true
                    appDelegate.configure(appState: appState)
                }
                .onChange(of: setupCompleted) { _, completed in
                    guard completed, !didConfigure else { return }
                    didConfigure = true
                    appDelegate.configure(appState: appState)
                }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.locale, resolvedLocale)
                .showInDock()
        }

        Window("Setup", id: "setup") {
            SetupWizardView(setupCompleted: $setupCompleted) {
                appDelegate.configure(appState: appState)
                didConfigure = true
            }
            .environment(appState)
            .environment(\.locale, resolvedLocale)
            .showInDock()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "showOverlay": true,
            "preserveClipboard": true,
            "showWaveform": WaveformDefaults.defaultEnabled,
        ])

        let state = AppState()
        let llmService = LLMService(appState: state)
        let service = TranscriptionService(appState: state, llmService: llmService)
        state.setTranscriptionService(service)
        state.setLLMService(llmService)
        _appState = State(initialValue: state)
        _transcriptionService = State(initialValue: service)
    }
}

private struct MenuBarIcon: View {
    let appState: AppState
    let setupCompleted: Bool
    @Environment(\.openWindow) private var openWindow

    /// The combined load state across Whisper and LLM models.
    /// Downloading/loading takes priority, then error, then default.
    private var effectiveLoadState: ModelLoadState {
        // If either is downloading, show download progress
        if case .downloading(let p) = appState.modelLoadState { return .downloading(progress: p) }
        if case .downloading(let p) = appState.llmLoadState { return .downloading(progress: p) }
        // If either is loading, show loading
        if appState.modelLoadState == .loading { return .loading }
        if appState.llmLoadState == .loading { return .loading }
        // If either has error, show error
        if case .error = appState.modelLoadState { return appState.modelLoadState }
        if case .error = appState.llmLoadState { return appState.llmLoadState }
        return appState.modelLoadState
    }

    var body: some View {
        Group {
            switch effectiveLoadState {
            case .downloading(let progress):
                Image(systemName: "arrow.down.circle", variableValue: progress)
            case .loading:
                Image(systemName: "arrow.down.circle")
                    .symbolEffect(.pulse)
            case .error:
                Image(systemName: "exclamationmark.triangle")
            default:
                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
            }
        }
        .task {
            if !setupCompleted {
                openWindow(id: "setup")
            }
        }
    }
}
