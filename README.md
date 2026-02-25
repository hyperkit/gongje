# Gongje 講嘢

A macOS menu bar app for on-device Cantonese speech-to-text using [WhisperKit](https://github.com/argmaxinc/WhisperKit), with optional on-device LLM text correction via [MLX Swift](https://github.com/ml-explore/mlx-swift-lm).

Press a hotkey, speak Cantonese, and the transcribed text is typed into whichever app you're using. All processing happens locally on your Mac — no internet, no cloud, no data leaves your machine.

## Features

- **On-device transcription** — Runs Whisper models locally via CoreML/Metal. No network required after model download.
- **LLM text correction** — Optional on-device LLM fixes homophone errors (同音錯字) and adds punctuation to Cantonese transcription. Runs locally via MLX Swift.
- **Written Chinese & Spoken Cantonese models** — OpenAI Whisper models for standard written Chinese (書面語), plus community models fine-tuned for spoken Cantonese (口語).
- **Setup wizard** — Guided 6-step first-launch setup for permissions, model download, LLM setup, and hotkey configuration.
- **VAD-based auto-send** — Text is sent automatically when WhisperKit's voice activity detection detects silence. No manual timing needed.
- **Audio cues** — Distinct sounds on recording start and stop so you know when the mic is ready.
- **Menu bar app** — Lives in the menu bar, out of the way. No Dock icon.
- **Floating overlay** — Shows real-time transcription progress in a small floating panel. Raw text in gray, LLM-corrected text in white.
- **Noise reduction** — Lightweight audio noise suppression (high-pass filter + spectral gating) via Accelerate/vDSP. Removes low-frequency rumble, AC hum, and ambient noise before transcription. Configurable strength, enabled by default.
- **Waveform visualizer** — Frequency spectrum bars behind the overlay, driven by real-time FFT on speech frequencies. Toggleable in Settings (default off on 8GB machines).
- **Configurable hotkey** — Default `Option-Space`, fully remappable.
- **Multiple model sizes** — From Small (~500 MB) to Large V3 (~3 GB). Auto-recommends based on your Mac's RAM.
- **Clipboard preservation** — Restores your clipboard after pasting transcribed text (configurable delay).
- **Crossover/Wine support** — Optional Ctrl-V paste for Windows apps running under Crossover/Wine.

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1 or later recommended)
- Xcode 16+ (to build)
- Microphone permission
- Accessibility permission (for text injection via simulated paste)

## Getting Started

### Build from source

```bash
# Clone
git clone https://github.com/anthropics/gongje.git
cd gongje

# Set up local signing config
cp Local.xcconfig.template Local.xcconfig
# Edit Local.xcconfig with your Apple Development team ID

# Generate Xcode project
brew install xcodegen  # if not installed
xcodegen generate

# Open and run
open gongje.xcodeproj
# Press Cmd-R to build and run
```

### First launch

On first launch, a setup wizard guides you through:

1. **Welcome** — Overview of what the wizard will configure
2. **Microphone** — Grant microphone access for audio capture
3. **Accessibility** — Grant accessibility permission for text injection (with buttons to open System Settings and reveal the app in Finder)
4. **Model** — Choose and download a Whisper model (auto-recommends based on RAM)
5. **LLM** — Optionally enable on-device LLM text correction and download a model
6. **Ready** — Configure the recording hotkey, then start using the app

On subsequent launches, the wizard is skipped and the app starts normally.

### Signing for development

The project uses `Local.xcconfig` for code signing settings (gitignored). Copy the template and fill in your values:

```bash
cp Local.xcconfig.template Local.xcconfig
```

To find your team ID:
```bash
security find-identity -v -p codesigning
```

For ad-hoc signing (no Apple Developer account):
```
DEVELOPMENT_TEAM =
CODE_SIGN_IDENTITY = -
CODE_SIGN_STYLE = Manual
```

> **Note:** Ad-hoc signing changes the binary signature on every build, so you'll need to re-grant Accessibility permission after each rebuild.

## Usage

| Action | Default |
|---|---|
| Start/stop recording | `Option-Space` (configurable) |
| Unload models | Click menu bar icon > Unload Models |
| Open settings | Click menu bar icon > Settings |
| Quit | Click menu bar icon > Quit |

### How it works

1. Press the hotkey — a "pop" sound confirms the mic is ready, the overlay shows "Listening..."
2. Speak Cantonese — the overlay shows in-progress transcription
3. Pause speaking — WhisperKit's VAD detects silence and the text is automatically pasted into the focused app
4. Continue speaking — new text appears, repeat
5. Press the hotkey again — a "pop" sound plays, any remaining text is pasted, and recording stops

## Project Structure

```
gongje/
├── gongje/
│   ├── App/                    # App entry point and delegate
│   ├── Models/                 # AppState, WhisperModel, LLMModel enums
│   ├── Services/               # Audio, transcription, text output, LLM correction
│   ├── Settings/               # Hotkey config, user preferences
│   ├── UI/                     # Menu bar, overlay, settings, permissions, setup wizard
│   └── Resources/              # Info.plist, entitlements, assets
├── gongjeTests/
├── docs/                       # Architecture and design documentation
├── project.yml                 # XcodeGen project spec
├── Local.xcconfig.template     # Signing config template
└── Local.xcconfig              # Your local signing config (gitignored)
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## Tech Stack

- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** — CoreML-optimized Whisper inference
- **[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)** — On-device LLM inference via MLX on Apple Silicon
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** — Global hotkey with SwiftUI recorder
- **SwiftUI** — Menu bar UI, settings, overlay
- **AppKit** — NSPanel for non-activating overlay, NSPasteboard + CGEvent for text injection

## License

[MIT](LICENSE)
