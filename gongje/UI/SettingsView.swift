import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            ModelSettingsView()
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
            PermissionsView()
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 680, height: 560)
    }
}

enum WaveformDefaults {
    static let defaultEnabled: Bool = {
        let ramGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return ramGB > 8
    }()
}

private struct GeneralSettingsView: View {
    @AppStorage("showOverlay") private var showOverlay = true
    @AppStorage("showWaveform") private var showWaveform = WaveformDefaults.defaultEnabled
    @AppStorage("autoPaste") private var autoPaste = false
    @AppStorage("voiceOverAnnouncements") private var voiceOverAnnouncements = true
    @AppStorage("preserveClipboard") private var preserveClipboard = true
    @AppStorage("crossoverPaste") private var crossoverPaste = false
    @AppStorage("crossoverPasteDelay") private var crossoverPasteDelay = 50
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 300
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appLanguageOverride") private var selectedLanguage: String = "system"
    @State private var accessibilityGranted = TextOutputService.isAccessibilityGranted

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language:", selection: $selectedLanguage) {
                    Text("System Default").tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "繁體中文（台灣）").tag("zh-Hant-TW")
                    Text(verbatim: "繁體中文（香港）").tag("zh-Hant-HK")
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    if newValue == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    UserDefaults.standard.synchronize()
                }
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
            }

            Section("Overlay") {
                Toggle("Show transcription overlay", isOn: $showOverlay)
                if showOverlay {
                    Toggle("Show waveform effect", isOn: $showWaveform)
                }
            }

            Section("Accessibility") {
                Toggle("VoiceOver announcements", isOn: $voiceOverAnnouncements)
                Text("Announce transcription results via VoiceOver when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Hands-free text input", isOn: $autoPaste)
                Text("Automatically paste transcribed text into the active app for a fully hands-free voice input experience. Requires Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if autoPaste && !accessibilityGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission is required for auto-paste.")
                            .font(.caption)
                        Spacer()
                        Button("Grant Access") {
                            TextOutputService.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }

                if autoPaste {
                    Toggle("Preserve clipboard after paste", isOn: $preserveClipboard)
                    if preserveClipboard {
                        HStack {
                            Text("Restore delay:")
                            Spacer()
                            TextField("", value: $clipboardRestoreDelay, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("ms")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Also send Ctrl+V (For Apps running under Crossover/Wine)", isOn: $crossoverPaste)
                    if crossoverPaste {
                        HStack {
                            Text("Ctrl+V delay:")
                            Spacer()
                            TextField("", value: $crossoverPasteDelay, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("ms")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Run Setup Wizard…") {
                    openWindow(id: "setup")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = TextOutputService.isAccessibilityGranted
        }
    }
}

private struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var diskUsage: String = String(localized: "Calculating...")
    @State private var showDeleteConfirmation = false

    private static var modelsBaseURL: URL { TranscriptionService.downloadBase }

    var body: some View {
        Form {
            Section("Whisper Model") {
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

                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.selectedModel.originalModelRepo ?? appState.selectedModel.modelRepo ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(appState.selectedModel.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    
                    if let url = appState.selectedModel.huggingFaceURL {
                        HStack {
                            Spacer()
                            Button("🤗 Open on Hugging Face") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Recommended: \(WhisperModel.systemRecommended.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if case .downloading(let progress) = appState.modelLoadState {
                    ProgressView(value: progress) {
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if case .error(let msg) = appState.modelLoadState {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        } else if appState.modelLoadState == .loaded {
                            Text("Model loaded")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if appState.modelLoadState == .loading {
                            Text("Loading & prewarming…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("First load may take a few minutes")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("Reload Model") {
                        Task { await appState.loadModel() }
                    }
                    .disabled(appState.modelLoadState.isInProgress)
                }
            }

            llmSection

            Section("Storage") {
                HStack {
                    Text("Downloaded models")
                    Spacer()
                    Text(diskUsage)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Show in Finder") {
                        let url = Self.modelsBaseURL
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: url.path) {
                            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.open(url)
                    }
                    Spacer()
                    Button("Delete All Models", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .disabled(appState.modelLoadState.isInProgress)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDiskUsage() }
        .confirmationDialog(
            "Delete all downloaded models?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteModels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded WhisperKit models (\(diskUsage)). You will need to re-download a model before recording.")
        }
    }

    private func refreshDiskUsage() {
        let url = Self.modelsBaseURL
        Task.detached {
            let size = Self.directorySize(url: url)
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            await MainActor.run {
                diskUsage = formatted
            }
        }
    }

    private func deleteModels() {
        let fm = FileManager.default
        let url = Self.modelsBaseURL
        try? fm.removeItem(at: url)
        refreshDiskUsage()
        Task {
            await MainActor.run {
                appState.modelLoadState = .notLoaded
            }
        }
    }

    // MARK: - LLM Section

    @ViewBuilder
    private var llmSection: some View {
        Section("Text Correction (LLM)") {
            @Bindable var state = appState
            Toggle("Enable LLM text correction", isOn: $state.llmEnabled)

            if appState.llmEnabled {
                Picker("Model:", selection: $state.selectedLLMModel) {
                    ForEach(LLMModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.selectedLLMModel.originalModelRepo ?? appState.selectedLLMModel.modelRepo ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(appState.selectedLLMModel.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let url = appState.selectedLLMModel.huggingFaceURL {
                        HStack {
                            Spacer()
                            Button("🤗 Open on Hugging Face") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if case .downloading(let progress) = appState.llmLoadState {
                    ProgressView(value: progress) {
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                    }
                }

                HStack {
                    if case .error(let msg) = appState.llmLoadState {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else if appState.llmLoadState == .loaded {
                        Text("Model loaded")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if appState.llmLoadState == .loading {
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reload LLM") {
                        Task { await appState.loadLLMModel() }
                    }
                    .disabled(appState.llmLoadState.isInProgress)
                }
            }
        }
    }

    private static func directorySize(url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }
}

private struct AboutSettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? "Gongje"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Description") {
                Text("An on-device Cantonese speech-to-text app for macOS. Powered by WhisperKit and optional local LLM text correction, all processing stays on your Mac — no internet connection or cloud services required.")
                    .font(.callout)
            }

            Section("Limitations") {
                VStack(alignment: .leading, spacing: 6) {
                    aboutBullet("Requires Apple Silicon (M1 or later)")
                    aboutBullet("Models must be downloaded before first use")
                    aboutBullet("Transcription accuracy varies by model size and audio quality")
                    aboutBullet("LLM text correction requires additional memory")
                }
                .font(.callout)
            }

            Section("Credits") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Libraries")
                        .font(.callout)
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 4) {
                        aboutBullet("WhisperKit — on-device speech recognition")
                        aboutBullet("MLX Swift — local LLM inference")
                        aboutBullet("KeyboardShortcuts — global hotkey support")
                        aboutBullet("Swift Transformers — tokenizer support")
                        aboutBullet("Jinja — template rendering")
                    }
                    .font(.callout)

                    Text("Models")
                        .font(.callout)
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 4) {
                        aboutBullet("OpenAI Whisper — base speech recognition model")
                        aboutBullet("Qwen (Alibaba) — base LLM model")
                        aboutBullet("Community fine-tunes by AlvanLii, JackyHoCL, lordjia")
                    }
                    .font(.callout)
                }
            }

            Section("Source Code") {
                HStack {
                    Text("This project is open source.")
                        .font(.callout)
                    Spacer()
                    Button("View on GitHub") {
                        if let url = URL(string: "https://github.com/hyperkit/gongje") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func aboutBullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }
}
