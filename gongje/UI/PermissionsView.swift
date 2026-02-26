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
            }

            Section("Accessibility") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .red)
                        if accessibilityGranted {
                            Text("Granted")
                        } else {
                            Text("Not granted — required for text injection")
                        }
                        Spacer()
                    }
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
