# Architecture

## Overview

Gongje is a macOS menu bar app that performs on-device Cantonese speech-to-text using WhisperKit, with optional on-device LLM text correction via MLX Swift. It captures microphone audio, transcribes it locally via a CoreML-optimized Whisper model, optionally refines the output with an LLM to fix homophone errors and add punctuation, shows a live floating overlay, and injects the transcribed text into the currently focused application.

## System Architecture

```
┌─────────────────────────────────────────────────┐
│ GongjeApp (@main)                               │
│ ├─ MenuBarExtra → MenuBarView                   │
│ ├─ Settings scene → SettingsView                │
│ ├─ Window("Setup") → SetupWizardView            │
│ └─ AppDelegate                                  │
│    ├─ NSPanel (floating overlay)                │
│    ├─ KeyboardShortcuts (global hotkey)          │
│    └─ Microphone permission + model loading      │
└──────────────────────┬──────────────────────────┘
                       │ owns
              ┌────────▼─────────────┐
              │ AppState             │
              │ (@Observable)        │
              │ ├ isRecording        │
              │ ├ confirmedText      │
              │ ├ hypothesisText     │
              │ ├ correctedText      │
              │ ├ modelLoadState     │
              │ ├ selectedModel      │
              │ ├ llmEnabled         │
              │ ├ selectedLLMModel   │
              │ ├ llmLoadState       │
              │ └ audioEnergy        │
              └────────┬─────────────┘
                       │ delegates to
          ┌────────────▼────────────┐
          │ TranscriptionService    │
          │ (actor)                 │
          │ ├ WhisperKit            │
          │ ├ AudioStreamTranscriber│
          │ ├ VAD flush + deferred  │
          │ └ Hallucination filter  │
          └──────┬──────────────────┘
                 │ raw text
          ┌──────▼──────────┐
          │ LLMService      │
          │ (actor)         │
          │ ├ MLX Swift     │
          │ ├ 300ms debounce│
          │ ├ Drift guard   │
          │ └ Sanitization  │
          └──────┬──────────┘
                 │ corrected text
          ┌──────▼──────────┐
          │ TextOutputService│
          │ (NSPasteboard +  │
          │  CGEvent Cmd/    │
          │  Ctrl-V)         │
          └─────────────────┘
```

## Key Components

### App Layer

**`GongjeApp.swift`** — The `@main` entry point. Creates `AppState` and `TranscriptionService` during `init()`, registers UserDefaults, and declares three scenes:
- `MenuBarExtra` — the menu bar icon and dropdown menu
- `Settings` — the settings window
- `Window("Setup")` — the first-launch setup wizard

On first launch (`setupCompleted` is false), the `MenuBarIcon` opens the setup wizard window. `appDelegate.configure()` is gated behind `setupCompleted` — it only runs after the wizard completes or on subsequent launches where setup is already done.

**`AppDelegate.swift`** — Handles non-SwiftUI responsibilities:
- Creates the floating `NSPanel` overlay (non-activating, HUD-style)
- Registers the global hotkey via KeyboardShortcuts
- Requests microphone permission and triggers model loading
- Observes `appState.isRecording` to show/hide the overlay panel

### Models

**`AppState.swift`** — Central `@Observable` state object shared via SwiftUI environment. Tracks recording state, transcription text (confirmed, hypothesis, and LLM-corrected), model load state for both Whisper and LLM (with download progress), selected models, and LLM enabled state. Delegates recording start/stop to `TranscriptionService`. Plays audio cues (`NSSound`) after streaming starts and stops. Holds a reference to `LLMService` for model loading. Provides `unloadAllModels()` to free memory by unloading both Whisper and LLM models. If the user starts recording with an unloaded model, `startRecording()` automatically reloads Whisper (showing loading status in the overlay) before beginning transcription, and reloads LLM in the background if enabled.

**`WhisperModel.swift`** — Enum of available Whisper model variants, organized into two `LanguageStyleGroup` categories:
- **Written Chinese** (書面語): OpenAI models (Small, Medium, Large V3) — produce standard written Chinese characters
- **Spoken Cantonese** (口語): Community models (Cantonese Small, Cantonese Large V3) — produce spoken Cantonese characters

Each model knows its display name, approximate size, minimum RAM, short description, HuggingFace URLs (original and CoreML repos), per-model `hallucinationPatterns` (exact-match phrases the model emits on silence), and an `llmCorrectionDistanceScale` that controls how aggressively the LLM drift guard allows edits. Provides `systemRecommended` based on physical memory.

**`LLMModel.swift`** — Enum of LLM model variants for text correction:
- `qwen25_05b` — Qwen 2.5 0.5B 4-bit (~400 MB)
- `qwen25_15b` — Qwen 2.5 1.5B 4-bit (~870 MB, default)
- `qwen25_3b` — Qwen 2.5 3B 4-bit (~1.8 GB)
- `qwen2Cantonese7b` — Local Cantonese 7B 4-bit (~4 GB, local-only)

Each model knows its HuggingFace ID (nil for local-only), display name, short description, minimum RAM, and local directory name. Remote models are downloaded via MLX; local models are resolved from the shared models directory.

### Services

**`TranscriptionService.swift`** — An `actor` that owns the WhisperKit instance and manages streaming transcription. Key responsibilities:

1. **Model loading** — Two-phase: download with progress callback, then initialize with `download: false` to skip re-downloading. Also provides `unloadModel()` to nil out the WhisperKit instance and free memory.
2. **Streaming** — Uses WhisperKit's `AudioStreamTranscriber` which handles audio capture, VAD, hallucination detection (compression ratio + logprob thresholds), and segment confirmation internally.
3. **Audio cues** — Plays a system sound ("Pop") before the audio hardware is reconfigured, with a brief delay to let it finish before recording starts.
4. **VAD-based flush with deferred accumulation** — When WhisperKit's VAD detects a pause and triggers a stream reset (clearing segments), the text is not flushed immediately. Instead it's accumulated in `deferredFlushText`. A 3-second timer starts — if no new speech arrives, the accumulated text is flushed. If new speech arrives, the timer is cancelled and the deferred text is cleared (the new decode already includes it). This prevents mid-sentence cutoffs from aggressive VAD.
5. **Hallucination filter** — Post-processing filter (`isValidTranscription`) rejects outputs containing bracket markers (`[`, `]`, `(`, `)`) and per-model hallucination phrases (exact match via `WhisperModel.hallucinationPatterns`). Hallucinated text is also suppressed from the overlay display.
7. **LLM correction** — After each transcription update, sends the raw text to `LLMService.correctText()` (non-blocking). On flush/stop, prefers `correctedText` over raw text for injection.
8. **Stop handling** — Stops the stream, combines any deferred text with remaining pending text, injects the result (preferring LLM-corrected text, after hallucination filtering), then purges the audio buffer for the next session.
9. **Audio buffer management** — Audio samples are purged only after the stream transcriber is fully stopped (`stopStreaming`), never during active streaming, to avoid corrupting the transcriber's internal offset tracking.

**`LLMService.swift`** — An `actor` managing on-device LLM inference for text correction. Key responsibilities:
1. **Model loading** — Loads models from HuggingFace (remote) or local directory via MLX Swift's `LLMModelFactory`
2. **Debounced correction** — 300ms debounce prevents flooding the LLM with rapid WhisperKit updates; each new request cancels the previous generation
3. **Streaming output** — Streams partial results to `appState.correctedText` as tokens generate
4. **Input sanitization** — Strips system-reminder blocks, HTML tags, and control blocks before sending to the model
5. **Output sanitization** — Detects blocked output markers, persona leaks, and prompt injection artifacts
6. **Drift guard** — Uses Levenshtein distance to reject LLM outputs that deviate too far from the original transcription, scaled by `WhisperModel.llmCorrectionDistanceScale`
7. **System prompt** — Instructs the model to fix homophone errors, add punctuation, preserve Cantonese (not convert to Mandarin), and output only corrected text

**`TextOutputService.swift`** — Stateless utility for text injection. Saves the current pasteboard contents, writes transcribed text, simulates Cmd-V via `CGEvent`, then restores the original clipboard after a configurable delay (default 300ms). Optionally also sends Ctrl-V for Windows apps running via Crossover/Wine (configurable delay, default 50ms). Also provides Accessibility permission checking and system settings navigation.

**`FrequencyAnalyzer.swift`** — Performs FFT via Accelerate/vDSP on raw audio samples to produce frequency band magnitudes for the waveform visualizer. Analyzes the speech range (85–4000 Hz) with logarithmic band spacing, using a fixed dB noise floor to suppress background noise from close mics like AirPods.

**`AudioEngine.swift`** — Thin wrapper around `AudioProcessor.requestRecordPermission()`. Audio capture is handled internally by `AudioStreamTranscriber`.

### UI

**`SetupWizardView.swift`** — A 6-step first-launch wizard (~560x440 centered window):
1. **Welcome** — App name, description, what the wizard will configure
2. **Microphone** — Permission request with status indicator, auto-advances on grant
3. **Accessibility** — "Open System Settings" and "Reveal App in Finder" buttons, polls `AXIsProcessTrusted()` every 2s, auto-advances on grant, "Skip for now" option
4. **Model Selection + Download** — Grouped picker (Written Chinese / Spoken Cantonese) pre-selected to `systemRecommended`, inline download progress
5. **LLM Setup** — Optional on-device LLM text correction. Toggle to enable, model picker, download progress, "Skip" option
6. **Ready** — Hotkey recorder, "Start Using Gongje" sets `setupCompleted = true`

**`MenuBarView.swift`** — The dropdown menu shown when clicking the menu bar icon. Displays:
- Status row with color-coded dot (model state: downloading, loading, ready, error)
- Text-based download progress bar (Unicode block characters, since NSMenu doesn't support SwiftUI ProgressView)
- Start/Stop recording button
- Model status rows for both Whisper and LLM (if enabled), showing loading/downloading/loaded state in the same style
- "Unload Models" button to free memory (disabled during recording, loading, or when already unloaded)
- Settings and Quit actions

**`MenuBarIcon`** (in `GongjeApp.swift`) — Dynamic SF Symbol in the menu bar. Reflects the combined load state of both Whisper and LLM models:
- `arrow.down.circle` with variable fill during download
- Pulsing `arrow.down.circle` during model loading
- `exclamationmark.triangle` on error
- `mic` / `mic.fill` for idle/recording
- Opens setup wizard on first launch when `setupCompleted` is false

**`TranscriptionOverlayView.swift`** — A floating HUD panel showing real-time transcription. Displays model loading/downloading status when auto-reloading on record. If LLM-corrected text is available, it's shown in white (confident); otherwise raw hypothesis text is shown in gray. Auto-hides when not recording. Positioned near the bottom center of the screen, movable by dragging. Optionally shows a `WaveformView` as a background layer when recording.

**`WaveformView.swift`** — A Canvas-based frequency spectrum visualizer shown behind the overlay text. Uses `FrequencyAnalyzer` to perform real-time FFT on raw audio samples, displaying 40 speech-frequency bars (85–4000 Hz) flanked by 12 static bars on each side. Bars are mirrored vertically from center with a fade at the edges. Renders at half the display refresh rate via `CVDisplayLink`, interpolating toward target values each frame for smooth animation. Toggled via "Show waveform effect" in Settings (default off on ≤8 GB RAM).

**`SettingsView.swift`** — Three-tab settings window (640x500):
- **General** — Hotkey recorder, overlay toggle, clipboard settings (preserve toggle with configurable restore delay, Crossover/Wine Ctrl-V toggle with configurable delay), "Run Setup Wizard..." button
- **Model** — Whisper model picker (grouped by Written Chinese / Spoken Cantonese) with model info (repo name, description, HuggingFace link), reload button, download progress. LLM text correction section with enable toggle, model picker with info, reload button. Storage management (disk usage, delete all, open in Finder)
- **Permissions** — Microphone and Accessibility status with action buttons

**`PermissionsView.swift`** — Inline permission status display used in Settings. Shows green/red indicators for Microphone and Accessibility, with buttons to open System Settings and reveal the app binary in Finder (useful for manually granting Accessibility access).

### Settings

**`HotkeyNames.swift`** — Declares `KeyboardShortcuts.Name.toggleRecording` with default `Option-Space`.

**`SettingsManager.swift`** — UserDefaults-backed preferences for overlay visibility, clipboard preservation, and selected model.

## Data Flow

### First Launch Flow

```
App launches (setupCompleted = false)
  → MenuBarIcon .task opens setup wizard window
  → AppDelegate.configure() is NOT called

Setup wizard:
  → Step 1: Welcome
  → Step 2: Grant microphone permission
  → Step 3: Grant accessibility permission (polls every 2s)
  → Step 4: Select Whisper model → download → load
  → Step 5: Enable LLM text correction (optional) → download → load
  → Step 6: Configure hotkey → "Start Using Gongje"
    → setupCompleted = true
    → appDelegate.configure() called directly
    → Wizard window closes

Subsequent launches (setupCompleted = true)
  → MenuBarIcon .task calls appDelegate.configure() immediately
  → Wizard skipped
```

### Recording Flow

```
User presses Option-Space
  → KeyboardShortcuts callback
    → AppState.toggleRecording()
      → AppState.startRecording()
        → isRecording = true
        → If model not loaded:
          → loadModel() (overlay shows "Loading model..." / "Downloading model...")
          → If load fails: isRecording = false, abort
          → If LLM enabled and not loaded: loadLLMModel() (background)
        → TranscriptionService.startStreaming()
          → Play "Pop" sound + 150ms delay
          → AudioStreamTranscriber.startStreamTranscription()
            → Microphone capture + VAD + Whisper inference

AudioStreamTranscriber state callback (continuous)
  → handleStateChange()
    → If stream reset (VAD detected pause, segments cleared):
      → Accumulate text in deferredFlushText
      → Start 3s flush timer
    → If new text arrives:
      → Cancel flush timer, clear deferred text (new decode includes it)
      → Update overlay with all accumulated text
      → Send raw text to LLMService.correctText() (async, 300ms debounce)
        → LLM streams corrected tokens → appState.correctedText
        → Overlay upgrades from gray (raw) to white (corrected)
    → If flush timer fires (3s of silence):
      → flushDeferred() → inject correctedText ?? rawText → Cmd-V (+Ctrl-V)
      → Clear overlay

User presses Option-Space again
  → AppState.toggleRecording()
    → AppState.stopRecording()
      → isRecording = false
      → Play "Pop" sound
      → TranscriptionService.stopStreaming()
        → Cancel flush timer, cancel LLM generation
        → Stop AudioStreamTranscriber
        → Combine deferred + pending text
        → Inject correctedText ?? rawText (after validation)
        → Purge audio buffer
        → Clear overlay
```

### Model Loading Flow

```
Setup wizard step 4 / App launch (if setupCompleted)
  → AppState.loadModel()
    → TranscriptionService.loadModel()
      → WhisperKit.download(progressCallback:)
        → AppState.modelLoadState = .downloading(progress)
        → Menu bar icon shows variable-fill arrow
      → WhisperKit(config) with download: false
        → AppState.modelLoadState = .loading
      → AppState.modelLoadState = .loaded

If LLM enabled (setup wizard step 5 / app launch):
  → AppState.loadLLMModel()
    → LLMService.loadModel()
      → LLMModelFactory.shared.loadContainer() (remote or local)
        → AppState.llmLoadState = .downloading(progress) / .loading
      → AppState.llmLoadState = .loaded
```

## Design Decisions

### Why NSPasteboard + CGEvent instead of Accessibility API text insertion?

Direct text insertion via AX APIs (`AXUIElementSetAttributeValue`) is unreliable across apps and doesn't handle CJK input methods well. Simulated Cmd-V via CGEvent works universally with any app that supports paste, including CJK text. The tradeoff is requiring Accessibility permission and temporarily using the clipboard (mitigated by save/restore).

### Why AudioStreamTranscriber instead of a manual transcription loop?

WhisperKit's `AudioStreamTranscriber` handles audio buffering, VAD (voice activity detection), hallucination filtering (compression ratio and logprob thresholds), and segment confirmation internally. A manual loop would need to reimplement all of these and is prone to issues like unbounded hallucination during silence.

### Why deferred flush instead of immediate VAD flush?

WhisperKit's VAD triggers stream resets at natural speech pauses, not just at end-of-speech. Flushing immediately on every stream reset causes text to be cut mid-sentence. The deferred approach accumulates text across stream resets and only flushes after 3 seconds of true silence (no new decode activity). If new speech arrives, the deferred text is cleared because WhisperKit's next decode cycle re-processes the same audio and produces the complete text.

### Why not purge audio during streaming?

Calling `purgeAudioSamples(keepingLast: 0)` during active streaming desynchronizes the `AudioStreamTranscriber`'s internal audio offset tracking from the `audioProcessor`'s buffer, causing subsequent decode cycles to produce empty results. Audio is only purged after the transcriber is fully stopped, ensuring a clean state for the next recording session.

### Why actor for TranscriptionService?

WhisperKit operations are async and involve mutable state (the streaming transcriber, deferred text, injected text tracking). Using a Swift actor ensures thread-safe access without manual locking.

### Why no App Sandbox?

The app needs to post `CGEvent` keyboard events (simulated Cmd-V) to inject text into other applications. This requires both Accessibility permission and unsandboxed execution, as sandboxed apps cannot post events to other processes.

### Why LSUIElement?

The app is a menu bar utility — it shouldn't appear in the Dock or the Cmd-Tab switcher. `LSUIElement = true` in Info.plist achieves this. Note: `SettingsLink` doesn't work in LSUIElement apps, so Settings is opened programmatically via `NSApp.sendAction(Selector(("showSettingsWindow:")))`.

### Why on-device LLM text correction?

Cantonese has many homophones (同音字), and Whisper frequently produces the wrong character with the same pronunciation. An on-device LLM post-processes the raw transcription to fix homophone errors and add missing punctuation. The LLM runs via MLX Swift on Apple Silicon, keeping all data local. A 300ms debounce prevents flooding the LLM, and a Levenshtein distance-based drift guard (scaled per Whisper model quality) rejects outputs that deviate too far from the original — ensuring the LLM corrects rather than rewrites.

### Why Crossover/Wine paste support?

Some users run Windows applications via Crossover/Wine on macOS. These apps respond to Ctrl-V (Windows paste) rather than Cmd-V (macOS paste). The dual paste mechanism sends both key combinations with a configurable delay between them.

### Why a setup wizard?

Without onboarding, new users see a menu bar icon appear, permissions get requested without explanation, and a large model download begins immediately. The 6-step wizard guides users through permissions, model selection, optional LLM setup, and hotkey configuration with context about why each step is needed. Setup state is persisted via `@AppStorage("setupCompleted")` so the wizard only appears once. A "Run Setup Wizard..." button in Settings allows re-running it.

### Why Local.xcconfig for signing?

Code signing settings (DEVELOPMENT_TEAM, CODE_SIGN_IDENTITY) are developer-specific and should not be committed to a public repository. Using a gitignored `Local.xcconfig` with a committed template keeps the project buildable by anyone while keeping sensitive values out of version control.

## Model Storage

All models (Whisper and LLM) are stored under `~/Documents/gongje/huggingface/`:
- Whisper models are downloaded via WhisperKit's built-in mechanism
- LLM models are downloaded via MLX Swift's `LLMModelFactory` or loaded from a local `models/` subdirectory
- Local-only models (e.g., Cantonese 7B) must be placed manually in `models/{directoryName}/`

This location is:
- Outside the app bundle (persists across rebuilds)
- In a user-accessible location (can be managed manually)
- Configurable via `TranscriptionService.downloadBase`

The Settings UI shows total disk usage and provides a delete button with confirmation.

## Permissions

The app requires two permissions:

1. **Microphone** (`NSMicrophoneUsageDescription`) — For audio capture. Requested during setup wizard or on first launch via `AudioProcessor.requestRecordPermission()`.

2. **Accessibility** (`AXIsProcessTrusted`) — For posting CGEvent keyboard events to simulate Cmd-V. Must be granted manually in System Settings > Privacy & Security > Accessibility. The setup wizard provides buttons to open System Settings and reveal the app in Finder. Note: ad-hoc code signing (`CODE_SIGN_IDENTITY: -`) changes the binary signature on every build, requiring re-granting Accessibility permission after each rebuild. Using `Automatic` signing with a real Development Team avoids this.
