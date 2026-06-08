import AppKit
import SwiftUI
import IconPingCore

extension Notification.Name {
    static let iconPingShowInDockChanged   = Notification.Name("IconPing.showInDockChanged")
    static let iconPingShowMenuBarChanged  = Notification.Name("IconPing.showMenuBarChanged")
}

@main
struct IconPingApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let showDock = defaults.bool(forKey: Preferences.Key.showInDock.rawValue)
        let showMenu = defaults.bool(forKey: Preferences.Key.showMenuBar.rawValue)
        let openDash = defaults.bool(forKey: Preferences.Key.openDashboardOnLaunch.rawValue)

        // Activation policy reflects "Show in Dock" preference.
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        let vm = AppViewModel()
        self.viewModel = vm

        if showMenu {
            self.menuBarController = MenuBarController(viewModel: vm)
        }

        vm.start()

        Task {
            await NotificationService.shared.requestAuthorizationIfNeeded()
        }

        // Auto-open the dashboard if the user asked for it OR if they've disabled
        // both Dock and menu bar (otherwise they'd have no way to find the app).
        let mustShowDashboard = openDash || (!showDock && !showMenu)
        if mustShowDashboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let vm = self?.viewModel else { return }
                WindowManager.shared.openDashboard(viewModel: vm)
            }
        }

        // Sleep / wake observers.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // Live preference observers.
        NotificationCenter.default.addObserver(
            self, selector: #selector(showInDockChanged),
            name: .iconPingShowInDockChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showMenuBarChanged),
            name: .iconPingShowMenuBarChanged, object: nil
        )

        // Debug screenshot path (CLI-driven).
        let env = ProcessInfo.processInfo.environment
        let shotDir = env["ICONPING_SHOT_DIR"]
        let exitAfter = env["ICONPING_EXIT_AFTER_MS"].flatMap(Int.init)

        if env["ICONPING_AUTO_DASHBOARD"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let vm = self?.viewModel else { return }
                WindowManager.shared.openDashboard(viewModel: vm)
                if let dir = shotDir {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        Self.renderWindow(WindowManager.shared.dashboardWindow_internal,
                                          to: "\(dir)/dashboard.png")
                    }
                }
            }
        }
        if env["ICONPING_AUTO_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let vm = self?.viewModel else { return }
                WindowManager.shared.openSettings(viewModel: vm)
                if let dir = shotDir {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        Self.renderWindow(WindowManager.shared.settingsWindow_internal,
                                          to: "\(dir)/settings.png")
                    }
                }
            }
        }

        if let ms = exitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }

    // When the user clicks the Dock icon and no window is open, open the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let vm = viewModel {
            WindowManager.shared.openDashboard(viewModel: vm)
        }
        return true
    }

    @objc private func didSleep() {
        guard let vm = viewModel else { return }
        if !vm.paused { vm.togglePause() }
    }

    @objc private func didWake() {
        guard let vm = viewModel else { return }
        if vm.paused { vm.togglePause() }
        vm.resetStats()
    }

    // MARK: - Live preference changes

    @objc private func showInDockChanged() {
        let showDock = UserDefaults.standard.bool(forKey: Preferences.Key.showInDock.rawValue)
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        ensureUserCanFindApp()
    }

    @objc private func showMenuBarChanged() {
        let showMenu = UserDefaults.standard.bool(forKey: Preferences.Key.showMenuBar.rawValue)
        if showMenu {
            if menuBarController == nil, let vm = viewModel {
                menuBarController = MenuBarController(viewModel: vm)
            }
        } else {
            menuBarController?.removeFromStatusBar()
            menuBarController = nil
        }
        ensureUserCanFindApp()
    }

    /// If the user disables both Dock and menu bar, force-open the dashboard
    /// so they can't lose access to the app entirely.
    private func ensureUserCanFindApp() {
        let showDock = UserDefaults.standard.bool(forKey: Preferences.Key.showInDock.rawValue)
        let showMenu = UserDefaults.standard.bool(forKey: Preferences.Key.showMenuBar.rawValue)
        guard !showDock && !showMenu, let vm = viewModel else { return }
        WindowManager.shared.openDashboard(viewModel: vm)
    }

    // MARK: - Debug screenshot helper

    static func renderWindow(_ window: NSWindow?, to path: String) {
        guard let window, let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        let props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        guard let png = rep.representation(using: .png, properties: props) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? png.write(to: url)
        NSLog("IconPing debug: wrote screenshot \(path) (\(Int(bounds.width))x\(Int(bounds.height)))")
    }
}
