import AppKit
import Carbon.HIToolbox

enum TextOutputService {
    static func injectText(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        let shouldPaste = autoPaste && isAccessibilityGranted
        let preserveClipboard = shouldPaste && UserDefaults.standard.bool(forKey: "preserveClipboard")

        // Save current clipboard (only when auto-paste will restore it)
        var previousItems: [NSPasteboardItem]?
        if preserveClipboard {
            previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
        }

        // Write text to clipboard (always — baseline behavior)
        pasteboard.clearContents()
        print("Set string to pasteboard: \(text)")
        pasteboard.setString(text, forType: .string)

        // Announce via VoiceOver (genuine accessibility feature)
        if UserDefaults.standard.bool(forKey: "voiceOverAnnouncements") {
            announceForVoiceOver(text)
        }

        // Simulate paste only when auto-paste is enabled and AX is granted
        guard shouldPaste else { return }

        simulatePaste(modifier: .maskCommand)

        // Also simulate Ctrl-V for Windows apps running via Crossover/Wine
        if UserDefaults.standard.bool(forKey: "crossoverPaste") {
            let delayMs = UserDefaults.standard.integer(forKey: "crossoverPasteDelay")
            let delay = max(0, delayMs)
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay) / 1000.0) {
                    simulatePaste(modifier: .maskControl)
                }
            } else {
                simulatePaste(modifier: .maskControl)
            }
        }

        // Restore clipboard after a delay
        let clipboardRestoreMs = max(0, UserDefaults.standard.integer(forKey: "clipboardRestoreDelay"))
        let clipboardRestoreDelay = clipboardRestoreMs > 0 ? Double(clipboardRestoreMs) / 1000.0 : 0.3
        let restoreDelay: Double
        if UserDefaults.standard.bool(forKey: "crossoverPaste") {
            let ctrlDelay = Double(max(0, UserDefaults.standard.integer(forKey: "crossoverPasteDelay")))
            restoreDelay = (ctrlDelay / 1000.0) + clipboardRestoreDelay
        } else {
            restoreDelay = clipboardRestoreDelay
        }
        if preserveClipboard, let previousItems {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                pasteboard.clearContents()
                pasteboard.writeObjects(previousItems)
            }
        }
    }

    private static func simulatePaste(modifier: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = modifier

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = modifier

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Announce transcription result via VoiceOver.
    /// Uses NSAccessibility posting which works without AXIsProcessTrusted
    /// and is a no-op when VoiceOver is inactive.
    static func announceForVoiceOver(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        // Prompt the system dialog first
        requestAccessibility()
        // Also open System Settings directly to the Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
