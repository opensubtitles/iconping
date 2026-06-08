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

        // Standard macOS application menu bar (App / File / View / Window / Help)
        setupMainMenu()

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

    // MARK: - Mac menu bar (top-of-screen menus)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // ─── App menu ───
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: String(format: NSLocalizedString("menu.about", value: "About %@", comment: ""), "IconPing"),
            action: #selector(menuShowAbout), keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let prefItem = NSMenuItem(
            title: NSLocalizedString("menu.preferences", value: "Settings…", comment: ""),
            action: #selector(menuShowSettings), keyEquivalent: ","
        )
        prefItem.target = self
        appMenu.addItem(prefItem)

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: String(format: NSLocalizedString("menu.hide", value: "Hide %@", comment: ""), "IconPing"),
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        let hideOthers = NSMenuItem(
            title: NSLocalizedString("menu.hideOthers", value: "Hide Others", comment: ""),
            action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.showAll", value: "Show All", comment: ""),
            action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""
        ))

        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.quit", value: "Quit IconPing", comment: ""),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))

        // ─── File menu ───
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: NSLocalizedString("menu.file", value: "File", comment: ""))
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.close", value: "Close Window", comment: ""),
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"
        ))

        // ─── View menu ───
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: NSLocalizedString("menu.view", value: "View", comment: ""))
        viewMenuItem.submenu = viewMenu

        let dashItem = NSMenuItem(
            title: NSLocalizedString("menu.dashboard", value: "Open Dashboard", comment: ""),
            action: #selector(menuShowDashboard), keyEquivalent: "d"
        )
        dashItem.target = self
        viewMenu.addItem(dashItem)

        let pauseItem = NSMenuItem(
            title: NSLocalizedString("menu.pauseResume", value: "Pause / Resume", comment: ""),
            action: #selector(menuTogglePause), keyEquivalent: "p"
        )
        pauseItem.target = self
        viewMenu.addItem(pauseItem)

        let resetItem = NSMenuItem(
            title: NSLocalizedString("action.reset", value: "Reset stats", comment: ""),
            action: #selector(menuResetStats), keyEquivalent: "r"
        )
        resetItem.target = self
        viewMenu.addItem(resetItem)

        // ─── Window menu (standard) ───
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: NSLocalizedString("menu.window", value: "Window", comment: ""))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.minimize", value: "Minimize", comment: ""),
            action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.zoom", value: "Zoom", comment: ""),
            action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""
        ))
        NSApp.windowsMenu = windowMenu

        // ─── Help menu ───
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: NSLocalizedString("menu.help", value: "Help", comment: ""))
        helpMenuItem.submenu = helpMenu
        let githubItem = NSMenuItem(
            title: NSLocalizedString("menu.openGitHub", value: "IconPing on GitHub", comment: ""),
            action: #selector(menuOpenGitHub), keyEquivalent: ""
        )
        githubItem.target = self
        helpMenu.addItem(githubItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuShowDashboard() {
        guard let vm = viewModel else { return }
        WindowManager.shared.openDashboard(viewModel: vm)
    }

    @objc private func menuShowSettings() {
        guard let vm = viewModel else { return }
        WindowManager.shared.openSettings(viewModel: vm)
    }

    @objc private func menuShowAbout() {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        let credits = NSAttributedString(
            string: NSLocalizedString("about.credit",
                value: "Inspired by antirez's original iconping. MIT license.",
                comment: ""
            ),
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "IconPing",
            .applicationVersion: version,
            .version: "(\(build))",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuTogglePause() {
        viewModel?.togglePause()
    }

    @objc private func menuResetStats() {
        viewModel?.resetStats()
    }

    @objc private func menuOpenGitHub() {
        if let url = URL(string: "https://github.com/opensubtitles/iconping") {
            NSWorkspace.shared.open(url)
        }
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
