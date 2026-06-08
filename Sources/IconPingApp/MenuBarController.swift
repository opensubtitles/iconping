import AppKit
import SwiftUI
import IconPingCore
import Combine

@MainActor
final class MenuBarController: NSObject {

    private let viewModel: AppViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var observers = Set<AnyCancellable>()

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 220)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: viewModel) { [weak self] in
                self?.closePopover()
            }
        )

        configureButton()
        bindViewModel()
        rebuildMenu()
    }

    // MARK: - status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        updateIcon(state: .unknown, latencyText: nil)
    }

    private func bindViewModel() {
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(state: state, latencyText: self?.latencyTextIfEnabled())
                self?.rebuildMenu()
            }
            .store(in: &observers)

        viewModel.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon(state: self?.viewModel.state ?? .unknown,
                                 latencyText: self?.latencyTextIfEnabled())
                self?.updateTooltip()
            }
            .store(in: &observers)
    }

    private func latencyTextIfEnabled() -> String? {
        guard UserDefaults.standard.bool(forKey: Preferences.Key.showLatencyText.rawValue) else { return nil }
        guard let ms = viewModel.snapshot.rttLastMs else { return nil }
        return String(format: "%.0f ms", ms)
    }

    private func updateIcon(state: ConnectivityState, latencyText: String?) {
        guard let button = statusItem.button else { return }
        let (symbol, tint) = symbolAndTint(for: state)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: state.rawValue)?
            .withSymbolConfiguration(config)
        image?.isTemplate = false // we want color
        if let image {
            let tinted = tintedImage(image, color: tint)
            button.image = tinted
        }
        button.title = latencyText ?? ""
    }

    private func updateTooltip() {
        let state = viewModel.state
        let snap = viewModel.snapshot
        let statusName = NSLocalizedString(state.localizationKey, comment: "")
        let lossFmt = String(format: NSLocalizedString("tooltip.loss", value: "%.0f%% loss", comment: ""), snap.lossPercent)
        if let ms = snap.rttLastMs {
            let rttFmt = String(format: NSLocalizedString("tooltip.rtt", value: "%.0f ms", comment: ""), ms)
            statusItem.button?.toolTip = "\(statusName) · \(rttFmt) · \(lossFmt)"
        } else {
            statusItem.button?.toolTip = "\(statusName) · \(lossFmt)"
        }
    }

    private func symbolAndTint(for state: ConnectivityState) -> (String, NSColor) {
        switch state {
        case .up:      return ("circle.fill",                NSColor.systemGreen)
        case .slow:    return ("circle.bottomhalf.filled",   NSColor.systemOrange)
        case .down:    return ("xmark.circle.fill",          NSColor.systemRed)
        case .unknown: return ("circle.dotted",              NSColor.secondaryLabelColor)
        }
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceIn)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    // MARK: - click handling

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown { closePopover() } else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() { popover.performClose(nil) }

    // MARK: - menu

    private func rebuildMenu() {
        // Menu is built on demand for right-click; left-click uses the popover.
        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusName = NSLocalizedString(viewModel.state.localizationKey, comment: "")
        let header = NSMenuItem(title: statusName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let dash = NSMenuItem(
            title: NSLocalizedString("menu.dashboard", value: "Open Dashboard", comment: ""),
            action: #selector(openDashboard),
            keyEquivalent: "d"
        )
        dash.target = self
        menu.addItem(dash)

        let settings = NSMenuItem(
            title: NSLocalizedString("menu.settings", value: "Settings…", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: NSLocalizedString("menu.loginItem", value: "Open at login", comment: ""),
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LaunchAtLoginService.shared.isEnabled ? .on : .off
        menu.addItem(login)

        let pauseTitle = viewModel.paused
            ? NSLocalizedString("menu.resume", value: "Resume monitoring", comment: "")
            : NSLocalizedString("menu.pause", value: "Pause monitoring", comment: "")
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("menu.quit", value: "Quit IconPing", comment: ""),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = nil // we present transiently — see showMenu()
        cachedMenu = menu
    }

    private var cachedMenu: NSMenu?

    private func showMenu() {
        guard let menu = cachedMenu, let button = statusItem.button else { return }
        let location = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    @objc private func openDashboard() {
        WindowManager.shared.openDashboard(viewModel: viewModel)
    }

    @objc private func openSettings() {
        WindowManager.shared.openSettings(viewModel: viewModel)
    }

    @objc private func toggleLogin() {
        let new = !LaunchAtLoginService.shared.isEnabled
        LaunchAtLoginService.shared.setEnabled(new)
        UserDefaults.standard.set(new, forKey: Preferences.Key.openAtLogin.rawValue)
        rebuildMenu()
    }

    @objc private func togglePause() {
        viewModel.togglePause()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Tear down the status item — used when the user disables "Show menu bar icon".
    func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
        observers.removeAll()
    }
}
