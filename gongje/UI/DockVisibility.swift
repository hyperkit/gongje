import AppKit
import SwiftUI

/// Manages dock icon visibility for a menu bar app.
///
/// When any tracked window is visible the app appears in the Dock and Cmd-Tab switcher.
/// When all tracked windows close the app hides from the Dock again.
@MainActor
enum DockVisibility {
    private static var visibleWindowCount = 0

    static func windowOpened() {
        visibleWindowCount += 1
        if visibleWindowCount == 1 {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func windowClosed() {
        visibleWindowCount = max(visibleWindowCount - 1, 0)
        if visibleWindowCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// A view modifier that shows the app in the Dock while the view is visible.
struct ShowInDock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { DockVisibility.windowOpened() }
            .onDisappear { DockVisibility.windowClosed() }
    }
}

extension View {
    func showInDock() -> some View {
        modifier(ShowInDock())
    }
}
