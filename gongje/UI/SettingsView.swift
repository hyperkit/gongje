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
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 640, height: 500)
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
    @AppStorage("preserveClipboard") private var preserveClipboard = true
    @AppStorage("crossoverPaste") private var crossoverPaste = false
    @AppStorage("crossoverPasteDelay") private var crossoverPasteDelay = 50
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 300
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appLanguageOverride") private var selectedLanguage: String = "system"
    @State private var showRestartAlert = false

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
                    showRestartAlert = true
                }
                Text("Restart Gongje to apply language changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Clipboard") {
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

            Section {
                Button("Run Setup Wizard…") {
                    openWindow(id: "setup")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                let url = Bundle.main.bundleURL
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
                NSApp.terminate(nil)
            }
        } message: {
            Text("Please restart Gongje to apply the language change.")
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
                    Text(appState.selectedLLMModel.huggingFaceID ?? appState.selectedLLMModel.rawValue)
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
                    } else {
                        Text("This model is local-only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
