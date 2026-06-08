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
