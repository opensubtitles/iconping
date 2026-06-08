import AppKit
import SwiftUI
import IconPingCore

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // Internal accessors used by the debug-screenshot path in IconPingApp.swift.
    var dashboardWindow_internal: NSWindow? { dashboardWindow }
    var settingsWindow_internal:  NSWindow? { settingsWindow }

    func openDashboard(viewModel: AppViewModel) {
        if let w = dashboardWindow {
            foregroundWindow(w)
            return
        }
        let host = NSHostingController(rootView: DashboardView(viewModel: viewModel))
        let window = NSWindow(contentViewController: host)
        window.title = "IconPing — Dashboard"
        window.setContentSize(NSSize(width: 620, height: 440))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.delegate = WindowDelegateProxy.shared
        dashboardWindow = window
        foregroundWindow(window)
    }

    func openSettings(viewModel: AppViewModel) {
        if let w = settingsWindow {
            foregroundWindow(w)
            return
        }
        let host = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: host)
        window.title = "IconPing — Settings"
        window.setContentSize(NSSize(width: 580, height: 560))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.delegate = WindowDelegateProxy.shared
        settingsWindow = window
        foregroundWindow(window)
    }

    func handleWindowClose(_ window: NSWindow) {
        if window === dashboardWindow { dashboardWindow = nil }
        if window === settingsWindow  { settingsWindow  = nil }
        if dashboardWindow == nil && settingsWindow == nil {
            // Only drop back to menu-bar-only mode if the user explicitly chose
            // to hide the Dock icon. Otherwise keep the Dock icon visible so they
            // can re-open the dashboard with one click.
            let showInDock = UserDefaults.standard.bool(forKey: Preferences.Key.showInDock.rawValue)
            if !showInDock {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func foregroundWindow(_ window: NSWindow) {
        // Promote to a regular foreground app while any window is visible — required
        // for an LSUIElement/accessory app to gain focus and appear on the current Space.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    static let shared = WindowDelegateProxy()
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            WindowManager.shared.handleWindowClose(window)
        }
    }
}
