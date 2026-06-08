import SwiftUI
import IconPingCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("settings.general", systemImage: "gearshape") }

            thresholdsTab
                .tabItem { Label("settings.thresholds", systemImage: "slider.horizontal.3") }

            appearanceTab
                .tabItem { Label("settings.appearance", systemImage: "paintbrush") }

            notificationsTab
                .tabItem { Label("settings.notifications", systemImage: "bell") }

            startupTab
                .tabItem { Label("settings.startup", systemImage: "power") }

            languageTab
                .tabItem { Label("settings.language", systemImage: "globe") }

            aboutTab
                .tabItem { Label("settings.about", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .padding(8)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                TextField("field.target", text: $viewModel.engineConfig.targetHost)
                Picker("field.ipVersion", selection: $viewModel.engineConfig.ipPreference) {
                    Text("ip.auto").tag(IPVersionPreference.auto)
                    Text("ip.v4").tag(IPVersionPreference.ipv4)
                    Text("ip.v6").tag(IPVersionPreference.ipv6)
                }

                HStack {
                    Text("field.interval")
                    Spacer()
                    Slider(value: $viewModel.engineConfig.intervalSeconds, in: 0.25...60, step: 0.25)
                        .frame(width: 200)
                    Text(String(format: "%.2f s", viewModel.engineConfig.intervalSeconds))
                        .monospacedDigit().frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("field.timeout")
                    Spacer()
                    Slider(value: $viewModel.engineConfig.timeoutSeconds, in: 0.25...30, step: 0.25)
                        .frame(width: 200)
                    Text(String(format: "%.2f s", viewModel.engineConfig.timeoutSeconds))
                        .monospacedDigit().frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("field.payload")
                    Spacer()
                    Stepper(value: $viewModel.engineConfig.payloadBytes, in: 0...1452, step: 8) {
                        Text("\(viewModel.engineConfig.payloadBytes) B").monospacedDigit()
                    }
                }
            }
            Section("settings.presets") {
                HStack(spacing: 10) {
                    Button {
                        viewModel.applyPreset(.default)
                    } label: { Text("preset.default") }

                    Button {
                        viewModel.applyPreset(.satellite)
                    } label: { Text("preset.satellite") }

                    Button {
                        viewModel.applyPreset(.lan)
                    } label: { Text("preset.lan") }
                }
            }
        }
        .padding()
    }

    // MARK: - Thresholds

    private var thresholdsTab: some View {
        Form {
            HStack {
                Text("field.latencyWarn")
                Spacer()
                Slider(value: $viewModel.thresholds.latencyWarnMs, in: 20...2000, step: 10)
                    .frame(width: 200)
                Text(String(format: "%.0f ms", viewModel.thresholds.latencyWarnMs))
                    .monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            Stepper(value: $viewModel.thresholds.failureDebounce, in: 1...20) {
                HStack { Text("field.failureDebounce"); Spacer(); Text("\(viewModel.thresholds.failureDebounce)") }
            }
            Stepper(value: $viewModel.thresholds.recoveryDebounce, in: 1...20) {
                HStack { Text("field.recoveryDebounce"); Spacer(); Text("\(viewModel.thresholds.recoveryDebounce)") }
            }
            Stepper(value: $viewModel.thresholds.rollingWindow, in: 10...3600, step: 10) {
                HStack { Text("field.rollingWindow"); Spacer(); Text("\(viewModel.thresholds.rollingWindow)") }
            }
            Toggle("ui.simpleMode", isOn: $viewModel.thresholds.simpleMode)
        }
        .padding()
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Toggle("ui.showLatencyText",
                   isOn: BindingHelper.userDefaultsBool(.showLatencyText))
            Toggle("ui.flashOnChange",
                   isOn: BindingHelper.userDefaultsBool(.flashOnChange))
            Toggle("ui.simpleMode", isOn: $viewModel.thresholds.simpleMode)
        }
        .padding()
    }

    // MARK: - Notifications

    private var notificationsTab: some View {
        Form {
            Toggle("notif.onDown", isOn: BindingHelper.userDefaultsBool(.notifyOnDown))
            Toggle("notif.onUp",   isOn: BindingHelper.userDefaultsBool(.notifyOnUp))
            HStack {
                Text("notif.throttle")
                Spacer()
                Stepper(value: BindingHelper.userDefaultsInt(.notifyThrottle), in: 5...3600, step: 5) {
                    Text("\(UserDefaults.standard.integer(forKey: Preferences.Key.notifyThrottle.rawValue)) s")
                }
            }
            Toggle("notif.sound", isOn: BindingHelper.userDefaultsBool(.notifySound))
        }
        .padding()
    }

    // MARK: - Startup

    private var startupTab: some View {
        Form {
            Toggle("menu.loginItem", isOn: Binding(
                get: { LaunchAtLoginService.shared.isEnabled },
                set: { newValue in
                    LaunchAtLoginService.shared.setEnabled(newValue)
                    UserDefaults.standard.set(newValue, forKey: Preferences.Key.openAtLogin.rawValue)
                }
            ))
        }
        .padding()
    }

    // MARK: - Language

    private var languageTab: some View {
        Form {
            Picker("settings.language", selection: BindingHelper.languageOverride()) {
                Text("language.system").tag(Optional<String>.none)
                Text("English").tag(Optional("en"))
                Text("Italiano").tag(Optional("it"))
                Text("Español").tag(Optional("es"))
                Text("Slovenčina").tag(Optional("sk"))
                Text("Français").tag(Optional("fr"))
            }
            Text("language.note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("IconPing").font(.title.bold())
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                .foregroundStyle(.secondary)
            Text("about.tagline")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.secondary)
            HStack {
                Link("about.github", destination: URL(string: "https://github.com/opensubtitles/iconping")!)
                Link("about.license", destination: URL(string: "https://github.com/opensubtitles/iconping/blob/main/LICENSE")!)
            }
            Text("about.credit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Spacer()
        }
        .padding()
    }
}

enum BindingHelper {
    static func userDefaultsBool(_ key: Preferences.Key) -> Binding<Bool> {
        Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: key.rawValue) },
            set: { UserDefaults.standard.set($0, forKey: key.rawValue) }
        )
    }

    static func userDefaultsInt(_ key: Preferences.Key) -> Binding<Int> {
        Binding<Int>(
            get: { UserDefaults.standard.integer(forKey: key.rawValue) },
            set: { UserDefaults.standard.set($0, forKey: key.rawValue) }
        )
    }

    static func languageOverride() -> Binding<String?> {
        Binding<String?>(
            get: {
                guard let arr = UserDefaults.standard.array(forKey: Preferences.Key.appleLanguages.rawValue) as? [String],
                      let first = arr.first else { return nil }
                return String(first.prefix(2))
            },
            set: { newValue in
                if let code = newValue {
                    UserDefaults.standard.set([code], forKey: Preferences.Key.appleLanguages.rawValue)
                } else {
                    UserDefaults.standard.removeObject(forKey: Preferences.Key.appleLanguages.rawValue)
                }
            }
        )
    }
}
