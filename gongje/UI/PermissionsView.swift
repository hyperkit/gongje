import SwiftUI
import AVFoundation

struct PermissionsView: View {
    @State private var micPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var accessibilityGranted = TextOutputService.isAccessibilityGranted

    var body: some View {
        Form {
            Section("Microphone") {
                HStack {
                    Image(systemName: micPermission == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(micPermission == .authorized ? .green : .red)
                    Text(micPermissionText)
                    Spacer()
                    if micPermission != .authorized {
                        Button("Request") {
                            Task {
                                _ = await AVCaptureDevice.requestAccess(for: .audio)
                                micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
                            }
                        }
                    }
                }
                Text("Gongje captures audio from your microphone to perform on-device speech recognition. All processing happens locally on your Mac — no audio is sent to any server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if micPermission == .denied {
                    Text("Open System Settings → Privacy & Security → Microphone, then enable Gongje.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Accessibility") {
                HStack {
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Granted")
                    } else {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                        Text("Not granted — optional")
                    }
                    Spacer()
                }
                Text("This permission enables the hands-free text input feature, which automatically pastes transcribed text into the active app by simulating a keyboard shortcut. Without it, transcribed text is copied to the clipboard for you to paste manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("VoiceOver announcements and all other features work without this permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !accessibilityGranted {
                    Text("Open System Settings → Privacy & Security → Accessibility, then add this app using the + button.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Open Settings") {
                            TextOutputService.openAccessibilitySettings()
                        }
                        Button("Reveal App in Finder") {
                            revealAppInFinder()
                        }
                    }
                }
            }

            Section {
                Button("Refresh Status") {
                    micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
                    accessibilityGranted = TextOutputService.isAccessibilityGranted
                }
            }
        }
        .formStyle(.grouped)
    }

    private var micPermissionText: LocalizedStringKey {
        switch micPermission {
        case .authorized: "Granted"
        case .denied: "Denied — open System Settings to enable"
        case .restricted: "Restricted"
        case .notDetermined: "Not yet requested"
        @unknown default: "Unknown"
        }
    }

    private func revealAppInFinder() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}
