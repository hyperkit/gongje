import SwiftUI
import AVFoundation
import KeyboardShortcuts

struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var setupCompleted: Bool
    var onComplete: () -> Void

    @State private var currentStep = 0
    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.accentColor : index < currentStep ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: WelcomeStep(onNext: { currentStep = 1 })
        case 1: MicrophoneStep(onNext: { currentStep = 2 }, onBack: { currentStep = 0 })
        case 2: AccessibilityStep(onNext: { currentStep = 3 }, onBack: { currentStep = 1 })
        case 3: ModelStep(onNext: { currentStep = 4 }, onBack: { currentStep = 2 })
        case 4: LLMStep(onNext: { currentStep = 5 }, onBack: { currentStep = 3 })
        case 5: ReadyStep(onFinish: finish, onBack: { currentStep = 4 })
        default: EmptyView()
        }
    }

    private func finish() {
        setupCompleted = true
        onComplete()
        dismiss()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void

    @AppStorage("appLanguageOverride") private var selectedLanguage: String = "system"
    @AppStorage("setupCompleted") private var setupCompleted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Gongje")
                .font(.title)
                .fontWeight(.semibold)

            Text("Voice-to-text, right where you type.\nThis wizard will help you set up:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Language:", selection: $selectedLanguage) {
                Text("System Default").tag("system")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "繁體中文（台灣）").tag("zh-Hant-TW")
                Text(verbatim: "繁體中文（香港）").tag("zh-Hant-HK")
            }
            .frame(maxWidth: 250)

            VStack(alignment: .leading, spacing: 6) {
                Label("Microphone access", systemImage: "mic")
                Label("Accessibility permission", systemImage: "accessibility")
                Label("Speech recognition model", systemImage: "cpu")
                Label("Text correction (optional)", systemImage: "text.badge.checkmark")
                Label("Keyboard shortcut", systemImage: "keyboard")
            }
            .font(.callout)
            .padding(.top, 4)

            Spacer()

            Button("Get Started") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .onAppear {
            if !setupCompleted {
                applyDefaultPrompts()
            }
        }
        .onChange(of: selectedLanguage) { _, newValue in
            applyLanguageOverride(newValue)
            applyDefaultPrompts()
        }
    }

    private func applyLanguageOverride(_ language: String) {
        if language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    private func applyDefaultPrompts() {
        let effectiveLang = LLMService.resolveEffectiveLanguage(for: selectedLanguage)
        SettingsManager.llmSystemPrompt = LLMService.defaultSystemPrompt(for: effectiveLang)
        SettingsManager.llmUserPromptTemplate = LLMService.defaultUserPromptTemplate(for: effectiveLang)
    }
}

// MARK: - Step 2: Microphone

private struct MicrophoneStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: micStatus == .authorized ? "mic.circle.fill" : "mic.circle")
                .font(.system(size: 48))
                .foregroundStyle(micStatus == .authorized ? Color.green : Color.accentColor)

            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Gongje needs microphone access to hear your voice and transcribe it into text.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            statusView

            Spacer()

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                Spacer()
                if micStatus == .authorized {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if micStatus == .denied {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Grant Access") {
                        requesting = true
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                            requesting = false
                            if micStatus == .authorized {
                                try? await Task.sleep(for: .milliseconds(500))
                                onNext()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(requesting)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 6) {
            Image(systemName: micStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(micStatus == .authorized ? .green : .red)
            Text(statusText)
                .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private var statusText: LocalizedStringKey {
        switch micStatus {
        case .authorized: "Microphone access granted"
        case .denied: "Denied — open System Settings to enable"
        case .restricted: "Restricted by system policy"
        case .notDetermined: "Not yet requested"
        @unknown default: "Unknown"
        }
    }
}

// MARK: - Step 3: Accessibility

private struct AccessibilityStep: View {
    var onNext: () -> Void
    var onBack: () -> Void

    @State private var granted = TextOutputService.isAccessibilityGranted
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: granted ? "accessibility.badge.arrow.up.right" : "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(granted ? Color.green : Color.accentColor)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Gongje uses Accessibility to type transcribed text into any app. You'll need to add Gongje in System Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                if granted {
                    Text("Accessibility access granted")
                        .font(.callout)
                } else {
                    Text("Waiting for permission...")
                        .font(.callout)
                }
            }
            .padding(.vertical, 4)

            if !granted {
                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        TextOutputService.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reveal App in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                Spacer()
                if granted {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Skip for now") { onNext() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let newValue = TextOutputService.isAccessibilityGranted
            if newValue != granted {
                granted = newValue
                if granted {
                    stopPolling()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onNext()
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - Step 4: Model Selection + Download

private struct ModelStep: View {
    @Environment(AppState.self) private var appState
    var onNext: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: modelIcon)
                .font(.system(size: 48))
                .foregroundStyle(appState.modelLoadState == .loaded ? Color.green : Color.accentColor)

            Text("Speech Recognition Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a model to download. Larger models are more accurate but use more memory and storage.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            @Bindable var state = appState
            Picker("Model:", selection: $state.selectedModel) {
                ForEach(WhisperModel.LanguageStyleGroup.allCases) { group in
                    Section(group.displayName) {
                        ForEach(WhisperModel.models(for: group)) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
            .disabled(appState.modelLoadState.isInProgress)

            Text("Recommended for your Mac: \(WhisperModel.systemRecommended.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            modelStatusView

            Spacer()

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                    .disabled(appState.modelLoadState.isInProgress)
                Spacer()
                if appState.modelLoadState == .loaded {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if case .error(let message) = appState.modelLoadState {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry Download") {
                            Task { await appState.loadModel() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Button("Download & Continue") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.modelLoadState.isInProgress)
                }
            }
        }
    }

    private var modelIcon: String {
        switch appState.modelLoadState {
        case .loaded: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle"
        default: "cpu"
        }
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch appState.modelLoadState {
        case .downloading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(maxWidth: 300)
                Text("Downloading... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .font(.callout)
            }
        case .error:
            EmptyView() // Error shown in bottom bar
        case .notLoaded:
            EmptyView()
        }
    }
}

// MARK: - Step 5: LLM Setup

private struct LLMStep: View {
    @Environment(AppState.self) private var appState
    var onNext: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: llmIcon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)

            Text("Text Correction")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Optionally enable on-device LLM to fix homophone errors in Cantonese transcription. This runs locally and requires extra memory.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            @Bindable var state = appState
            Toggle("Enable text correction", isOn: $state.llmEnabled)
                .frame(maxWidth: 300)

            if appState.llmEnabled {
                Picker("Model:", selection: $state.selectedLLMModel) {
                    ForEach(LLMModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .frame(maxWidth: 300)
                .disabled(appState.llmLoadState.isInProgress)

                llmStatusView
            }

            Spacer()

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                    .disabled(appState.llmLoadState.isInProgress)
                Spacer()
                if !appState.llmEnabled {
                    Button("Skip") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if appState.llmLoadState == .loaded {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if case .error(let message) = appState.llmLoadState {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry") {
                            Task { await appState.loadLLMModel() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Button("Download & Continue") {
                        Task {
                            await appState.loadLLMModel()
                            if appState.llmLoadState == .loaded {
                                onNext()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.llmLoadState.isInProgress)
                }
            }
        }
    }

    private var llmIcon: String {
        switch appState.llmLoadState {
        case .loaded where appState.llmEnabled: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle"
        default: "text.badge.checkmark"
        }
    }

    private var iconColor: Color {
        switch appState.llmLoadState {
        case .loaded where appState.llmEnabled: .green
        case .error: .red
        default: .accentColor
        }
    }

    @ViewBuilder
    private var llmStatusView: some View {
        switch appState.llmLoadState {
        case .downloading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(maxWidth: 300)
                Text("Downloading... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .font(.callout)
            }
        case .error, .notLoaded:
            EmptyView()
        }
    }
}

// MARK: - Step 6: Ready

private struct ReadyStep: View {
    var onFinish: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Configure your recording hotkey, then start using Gongje.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(spacing: 12) {
                    KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)

                    Text("Press this shortcut to start/stop voice recording. Default is Option + Space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
            }
            .frame(maxWidth: 300)

            Spacer()

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Start Using Gongje") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
