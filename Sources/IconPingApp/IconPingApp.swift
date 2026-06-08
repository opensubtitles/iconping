import AppKit
import SwiftUI
import IconPingCore

@main
struct IconPingApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: AppViewModel?
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = AppViewModel()
        self.viewModel = vm
        self.menuBarController = MenuBarController(viewModel: vm)
        vm.start()

        Task {
            await NotificationService.shared.requestAuthorizationIfNeeded()
        }

        // Debug: env-flag auto-open of windows so we can screenshot from CLI.
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }

    @objc private func didSleep() {
        guard let vm = viewModel else { return }
        if !vm.paused { vm.togglePause() }
    }

    @objc private func didWake() {
        guard let vm = viewModel else { return }
        // resume + reset transient
        if vm.paused { vm.togglePause() }
        vm.resetStats()
    }
}
