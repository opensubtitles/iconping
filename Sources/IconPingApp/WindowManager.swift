import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func openDashboard(viewModel: AppViewModel) {
        if let w = dashboardWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: DashboardView(viewModel: viewModel))
        let window = NSWindow(contentViewController: host)
        window.title = "IconPing — Dashboard"
        window.setContentSize(NSSize(width: 760, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = WindowDelegateProxy.shared
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = window
    }

    func openSettings(viewModel: AppViewModel) {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: host)
        window.title = "IconPing — Settings"
        window.setContentSize(NSSize(width: 540, height: 440))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = WindowDelegateProxy.shared
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func handleWindowClose(_ window: NSWindow) {
        if window === dashboardWindow { dashboardWindow = nil }
        if window === settingsWindow  { settingsWindow  = nil }
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
