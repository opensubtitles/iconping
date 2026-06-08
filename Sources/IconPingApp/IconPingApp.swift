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
    /// True iff we (not the user) paused the engine because the system went to
    /// sleep. Used to avoid silently resuming a session the user had manually
    /// paused before sleep.
    private var systemPausedOnSleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL: instantiate Preferences.shared *before* reading anything,
        // so registerDefaults() runs and the bool/int reads below see real
        // defaults instead of false/0 (Apple's fallback for unregistered keys).
        // Also normalize any garbage-on-disk values to safe ones in the same step.
        let prefs = Preferences.shared
        prefs.engineConfig = prefs.engineConfig
        prefs.thresholds   = prefs.thresholds

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

        // Background update check ~5 s after launch — silent if up-to-date or
        // if GitHub is unreachable; alerts only when an update is actually
        // available, so it isn't annoying.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self.runUpdateCheck(silent: true)
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

        // Optional auto-trigger of the Speed Test (for screenshot verification).
        if let trig = env["ICONPING_AUTO_SPEEDTEST_MS"].flatMap(Int.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(trig)) { [weak self] in
                self?.viewModel?.startSpeedTest()
            }
        }
        if let shotAt = env["ICONPING_SHOT_AT_MS"].flatMap(Int.init), let dir = shotDir {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(shotAt)) {
                Self.renderWindow(WindowManager.shared.dashboardWindow_internal,
                                  to: "\(dir)/dashboard-shot-\(shotAt)ms.png")
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
                // Take one final screenshot of whichever debug window is open,
                // so callers can run the app for N seconds and see the result.
                if let dir = shotDir {
                    if env["ICONPING_AUTO_DASHBOARD"] == "1" {
                        Self.renderWindow(WindowManager.shared.dashboardWindow_internal,
                                          to: "\(dir)/dashboard-final.png")
                    }
                    if env["ICONPING_AUTO_SETTINGS"] == "1" {
                        Self.renderWindow(WindowManager.shared.settingsWindow_internal,
                                          to: "\(dir)/settings-final.png")
                    }
                }
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
        if vm.paused {
            // User had already paused — leave it alone, remember that.
            systemPausedOnSleep = false
        } else {
            vm.togglePause()
            systemPausedOnSleep = true
        }
    }

    @objc private func didWake() {
        guard let vm = viewModel else { return }
        // Only auto-resume if WE paused on sleep. If the user paused manually,
        // they expect to still be paused on wake.
        if systemPausedOnSleep && vm.paused {
            vm.togglePause()
            vm.resetStats()
        }
        systemPausedOnSleep = false
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

        let updateItem = NSMenuItem(
            title: NSLocalizedString("menu.checkForUpdates", value: "Check for Updates…", comment: ""),
            action: #selector(menuCheckForUpdates), keyEquivalent: ""
        )
        updateItem.target = self
        appMenu.addItem(updateItem)

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

    @objc private func menuCheckForUpdates() {
        Task { @MainActor in
            await self.runUpdateCheck(silent: false)
        }
    }

    /// `silent: true` is used by the optional background-on-launch check —
    /// alerts only when there IS an update, never when up-to-date or on error.
    @MainActor
    func runUpdateCheck(silent: Bool) async {
        let result = await UpdateChecker().check()
        switch result {
        case .upToDate(let current):
            if silent { return }
            let a = NSAlert()
            a.messageText = NSLocalizedString("update.upToDate.title",
                value: "You're up to date", comment: "")
            a.informativeText = String(
                format: NSLocalizedString("update.upToDate.body",
                    value: "IconPing %d.%d.%d is the latest version.", comment: ""),
                current.major, current.minor, current.patch
            )
            a.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        case .updateAvailable(let current, let latest):
            let a = NSAlert()
            a.messageText = String(
                format: NSLocalizedString("update.available.title",
                    value: "IconPing %@ is available", comment: ""),
                latest.tagName
            )
            a.informativeText = String(
                format: NSLocalizedString("update.available.body",
                    value: "You're running %d.%d.%d. Open the Releases page to download.",
                    comment: ""),
                current.major, current.minor, current.patch
            )
            a.addButton(withTitle: NSLocalizedString("update.openReleases",
                value: "Open Releases", comment: ""))
            a.addButton(withTitle: NSLocalizedString("update.later",
                value: "Later", comment: ""))
            NSApp.activate(ignoringOtherApps: true)
            let response = a.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(latest.htmlURL)
            }
        case .error(let msg):
            if silent { return }
            let a = NSAlert()
            a.messageText = NSLocalizedString("update.error.title",
                value: "Update check failed", comment: "")
            a.informativeText = msg
            a.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
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
