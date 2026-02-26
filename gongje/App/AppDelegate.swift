import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSPanel?
    private var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
        setupOverlayWindow()
        setupHotkey()

        Task {
            let granted = await AudioEngine.requestPermission()
            if !granted {
                print("[Gongje] Microphone permission denied")
            }
            await appState.loadModel()
            if appState.llmEnabled {
                await appState.loadLLMModel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState, appState.isRecording else { return }
        Task { @MainActor in
            appState.toggleRecording()
        }
    }

    private func setupOverlayWindow() {
        guard let appState else { return }

        let overlayView = TranscriptionOverlayView()
            .environment(appState)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: overlayView)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 200
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        overlayWindow = panel

        Task { @MainActor in
            observeRecordingState()
        }
    }

    @MainActor
    private func observeRecordingState() {
        guard let appState else { return }

        withObservationTracking {
            _ = appState.isRecording
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let isRecording = self.appState?.isRecording ?? false
                let showOverlay = UserDefaults.standard.bool(forKey: "showOverlay")
                if isRecording && showOverlay {
                    self.overlayWindow?.orderFront(nil)
                } else {
                    self.overlayWindow?.orderOut(nil)
                }
                self.observeRecordingState()
            }
        }
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.appState?.toggleRecording()
            }
        }
    }
}
