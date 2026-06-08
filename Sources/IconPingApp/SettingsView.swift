import SwiftUI
import IconPingCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selection: String = ProcessInfo.processInfo.environment["ICONPING_SETTINGS_TAB"] ?? "general"

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("settings.general", systemImage: "gearshape") }
                .tag("general")
            ThresholdsTab(viewModel: viewModel)
                .tabItem { Label("settings.thresholds", systemImage: "slider.horizontal.3") }
                .tag("thresholds")
            AppearanceTab(viewModel: viewModel)
                .tabItem { Label("settings.appearance", systemImage: "paintbrush") }
                .tag("appearance")
            NotificationsTab()
                .tabItem { Label("settings.notifications", systemImage: "bell") }
                .tag("notifications")
            AboutTab()
                .tabItem { Label("settings.about", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: 580, height: 560)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel

    private var isTargetValid: Bool {
        Preferences.isValidTargetHost(
            viewModel.engineConfig.targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        Form {
            Section("settings.general") {
                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("", text: $viewModel.engineConfig.targetHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isTargetValid ? Color.clear : Color.red, lineWidth: 1)
                            )
                        if !isTargetValid {
                            Text("field.target.invalid")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .frame(width: 240, alignment: .leading)
                        }
                    }
                } label: {
                    Text(LocalizedStringKey("field.target"))
                }
                LabeledContent {
                    Picker("", selection: $viewModel.engineConfig.ipPreference) {
                        Text("ip.auto").tag(IPVersionPreference.auto)
                        Text("ip.v4").tag(IPVersionPreference.ipv4)
                        Text("ip.v6").tag(IPVersionPreference.ipv6)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("field.ipVersion"))
                }
                LabeledContent {
                    HStack {
                        Slider(value: $viewModel.engineConfig.intervalSeconds, in: 0.25...10, step: 0.25)
                            .frame(width: 170)
                        Text(String(format: "%.2fs", viewModel.engineConfig.intervalSeconds))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                } label: {
                    Text(LocalizedStringKey("field.interval"))
                }
                LabeledContent {
                    HStack {
                        Slider(value: $viewModel.engineConfig.timeoutSeconds, in: 0.25...10, step: 0.25)
                            .frame(width: 170)
                        Text(String(format: "%.2fs", viewModel.engineConfig.timeoutSeconds))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                } label: {
                    Text(LocalizedStringKey("field.timeout"))
                }
                LabeledContent {
                    Stepper(value: $viewModel.engineConfig.payloadBytes, in: 0...1452, step: 8) {
                        Text("\(viewModel.engineConfig.payloadBytes) B").monospacedDigit()
                    }
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("field.payload"))
                }
            }

            Section("settings.presets") {
                HStack(spacing: 8) {
                    Button {
                        viewModel.applyPreset(.default)
                    } label: { Text("preset.default").frame(maxWidth: .infinity) }
                    Button {
                        viewModel.applyPreset(.satellite)
                    } label: { Text("preset.satellite").frame(maxWidth: .infinity) }
                    Button {
                        viewModel.applyPreset(.lan)
                    } label: { Text("preset.lan").frame(maxWidth: .infinity) }
                }
                Toggle(isOn: BindingHelper.launchAtLogin()) {
                    Text(LocalizedStringKey("menu.loginItem"))
                }
                Toggle(isOn: BindingHelper.userDefaultsBool(.openDashboardOnLaunch)) {
                    Text(LocalizedStringKey("ui.openDashboardOnLaunch"))
                }
            }

            Section {
                Button(role: .destructive) {
                    Preferences.shared.resetToDefaults()
                    viewModel.engineConfig = Preferences.shared.engineConfig
                    viewModel.thresholds   = Preferences.shared.thresholds
                } label: {
                    Text(LocalizedStringKey("action.resetAll"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Thresholds

private struct ThresholdsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("settings.thresholds") {
                LabeledContent {
                    HStack {
                        Slider(value: $viewModel.thresholds.latencyWarnMs, in: 20...2000, step: 10)
                            .frame(width: 170)
                        Text(String(format: "%.0f ms", viewModel.thresholds.latencyWarnMs))
                            .monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                } label: {
                    Text(LocalizedStringKey("field.latencyWarn"))
                }
                LabeledContent {
                    Stepper(value: $viewModel.thresholds.failureDebounce, in: 1...20) {
                        Text("\(viewModel.thresholds.failureDebounce)").monospacedDigit()
                    }
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("field.failureDebounce"))
                }
                LabeledContent {
                    Stepper(value: $viewModel.thresholds.recoveryDebounce, in: 1...20) {
                        Text("\(viewModel.thresholds.recoveryDebounce)").monospacedDigit()
                    }
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("field.recoveryDebounce"))
                }
                LabeledContent {
                    Stepper(value: $viewModel.thresholds.rollingWindow, in: 10...3600, step: 10) {
                        Text("\(viewModel.thresholds.rollingWindow)").monospacedDigit()
                    }
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("field.rollingWindow"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance + Language

private struct AppearanceTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("settings.visibility") {
                Toggle(isOn: BindingHelper.userDefaultsBoolWithNotification(
                    .showInDock, notification: .iconPingShowInDockChanged
                )) {
                    Text(LocalizedStringKey("ui.showInDock"))
                }
                Toggle(isOn: BindingHelper.userDefaultsBoolWithNotification(
                    .showMenuBar, notification: .iconPingShowMenuBarChanged
                )) {
                    Text(LocalizedStringKey("ui.showMenuBar"))
                }
                Text("ui.visibilityHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.appearance") {
                Toggle(isOn: BindingHelper.userDefaultsBool(.showLatencyText)) {
                    Text(LocalizedStringKey("ui.showLatencyText"))
                }
                Toggle(isOn: BindingHelper.userDefaultsBool(.flashOnChange)) {
                    Text(LocalizedStringKey("ui.flashOnChange"))
                }
                Toggle(isOn: $viewModel.thresholds.simpleMode) {
                    Text(LocalizedStringKey("ui.simpleMode"))
                }
            }

            Section("settings.language") {
                LabeledContent {
                    Picker("", selection: BindingHelper.languageOverride()) {
                        Text("language.system").tag(Optional<String>.none)
                        Divider()
                        Text("English").tag(Optional("en"))
                        Text("Italiano").tag(Optional("it"))
                        Text("Español").tag(Optional("es"))
                        Text("Slovenčina").tag(Optional("sk"))
                        Text("Français").tag(Optional("fr"))
                    }
                    .labelsHidden()
                    .frame(width: 240)
                } label: {
                    Text(LocalizedStringKey("settings.language"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("language.fallback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("language.note")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @State private var throttle: Int = UserDefaults.standard.integer(forKey: Preferences.Key.notifyThrottle.rawValue)

    var body: some View {
        Form {
            Section("settings.notifications") {
                Toggle(isOn: BindingHelper.userDefaultsBool(.notifyOnDown)) {
                    Text(LocalizedStringKey("notif.onDown"))
                }
                Toggle(isOn: BindingHelper.userDefaultsBool(.notifyOnUp)) {
                    Text(LocalizedStringKey("notif.onUp"))
                }
                Toggle(isOn: BindingHelper.userDefaultsBool(.notifySound)) {
                    Text(LocalizedStringKey("notif.sound"))
                }
                LabeledContent {
                    Stepper(value: $throttle, in: 5...3600, step: 5) {
                        Text("\(throttle) s").monospacedDigit()
                    }
                    .frame(width: 240)
                    .onChange(of: throttle) { new in
                        UserDefaults.standard.set(new, forKey: Preferences.Key.notifyThrottle.rawValue)
                    }
                } label: {
                    Text(LocalizedStringKey("notif.throttle"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 8)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("IconPing")
                .font(.title2.bold())
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(LocalizedStringKey("about.tagline"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .foregroundStyle(.secondary)
                .font(.callout)
            HStack(spacing: 14) {
                Link(destination: URL(string: "https://github.com/opensubtitles/iconping")!) {
                    Label("about.github", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/opensubtitles/iconping/blob/main/LICENSE")!) {
                    Label("about.license", systemImage: "doc.text")
                }
            }
            .padding(.top, 4)
            Spacer()
            Text(LocalizedStringKey("about.credit"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bindings

enum BindingHelper {
    static func userDefaultsBool(_ key: Preferences.Key) -> Binding<Bool> {
        Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: key.rawValue) },
            set: { UserDefaults.standard.set($0, forKey: key.rawValue) }
        )
    }

    /// Like `userDefaultsBool` but also posts a Notification when changed, so
    /// AppDelegate can react live (e.g. flip activation policy, add/remove
    /// menu-bar status item) without restarting the app.
    static func userDefaultsBoolWithNotification(
        _ key: Preferences.Key,
        notification: Notification.Name
    ) -> Binding<Bool> {
        Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: key.rawValue) },
            set: { value in
                UserDefaults.standard.set(value, forKey: key.rawValue)
                NotificationCenter.default.post(name: notification, object: nil)
            }
        )
    }

    static func languageOverride() -> Binding<String?> {
        // We track our own override flag, separate from the system's AppleLanguages
        // (which exists for every user). nil = use system default; .some = override.
        let overrideKey = "iconping.langOverrideEnabled"
        return Binding<String?>(
            get: {
                guard UserDefaults.standard.bool(forKey: overrideKey) else { return nil }
                guard let arr = UserDefaults.standard.array(forKey: Preferences.Key.appleLanguages.rawValue) as? [String],
                      let first = arr.first else { return nil }
                return String(first.prefix(2))
            },
            set: { newValue in
                if let code = newValue {
                    UserDefaults.standard.set(true, forKey: overrideKey)
                    UserDefaults.standard.set([code], forKey: Preferences.Key.appleLanguages.rawValue)
                } else {
                    UserDefaults.standard.set(false, forKey: overrideKey)
                    UserDefaults.standard.removeObject(forKey: Preferences.Key.appleLanguages.rawValue)
                }
            }
        )
    }

    @MainActor
    static func launchAtLogin() -> Binding<Bool> {
        Binding<Bool>(
            get: { LaunchAtLoginService.shared.isEnabled },
            set: { newValue in
                LaunchAtLoginService.shared.setEnabled(newValue)
                UserDefaults.standard.set(newValue, forKey: Preferences.Key.openAtLogin.rawValue)
            }
        )
    }
}
