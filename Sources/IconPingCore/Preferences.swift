import Foundation

/// Typed wrapper around UserDefaults so the rest of the code uses a strict API.
/// SwiftUI views can additionally use `@AppStorage` with the same keys.
public final class Preferences: @unchecked Sendable {

    public enum Key: String, Sendable {
        // engine
        case targetHost      = "engine.targetHost"
        case ipPreference    = "engine.ipPreference"        // "auto" | "ipv4" | "ipv6"
        case intervalMs      = "engine.intervalMs"
        case timeoutMs       = "engine.timeoutMs"
        case payloadBytes    = "engine.payloadBytes"

        // thresholds
        case latencyWarnMs   = "thresholds.latencyWarnMs"
        case failureDebounce = "thresholds.failureDebounce"
        case recoveryDebounce = "thresholds.recoveryDebounce"
        case rollingWindow   = "thresholds.rollingWindow"
        case simpleMode      = "ui.simpleMode"

        // appearance
        case showLatencyText = "ui.showLatencyText"
        case flashOnChange   = "ui.flashOnChange"

        // notifications
        case notifyOnDown    = "notifications.onDown"
        case notifyOnUp      = "notifications.onUp"
        case notifyThrottle  = "notifications.throttleSeconds"
        case notifySound     = "notifications.sound"

        // launch
        case openAtLogin     = "launch.openAtLogin"

        // language override
        case appleLanguages  = "AppleLanguages"
    }

    public static let shared = Preferences()
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.targetHost.rawValue:        "1.1.1.1",
            Key.ipPreference.rawValue:      IPVersionPreference.auto.rawValue,
            Key.intervalMs.rawValue:        1000,
            Key.timeoutMs.rawValue:         2000,
            Key.payloadBytes.rawValue:      56,
            Key.latencyWarnMs.rawValue:     300,
            Key.failureDebounce.rawValue:   2,
            Key.recoveryDebounce.rawValue:  1,
            Key.rollingWindow.rawValue:     60,
            Key.simpleMode.rawValue:        false,
            Key.showLatencyText.rawValue:   false,
            Key.flashOnChange.rawValue:     false,
            Key.notifyOnDown.rawValue:      true,
            Key.notifyOnUp.rawValue:        true,
            Key.notifyThrottle.rawValue:    60,
            Key.notifySound.rawValue:       false,
            Key.openAtLogin.rawValue:       false
        ])
    }

    // MARK: - typed accessors

    public var engineConfig: EngineConfig {
        get {
            EngineConfig(
                targetHost:      defaults.string(forKey: Key.targetHost.rawValue) ?? "1.1.1.1",
                ipPreference:    IPVersionPreference(rawValue: defaults.string(forKey: Key.ipPreference.rawValue) ?? "auto") ?? .auto,
                intervalSeconds: Double(defaults.integer(forKey: Key.intervalMs.rawValue)) / 1000.0,
                timeoutSeconds:  Double(defaults.integer(forKey: Key.timeoutMs.rawValue)) / 1000.0,
                payloadBytes:    defaults.integer(forKey: Key.payloadBytes.rawValue)
            )
        }
        set {
            defaults.set(newValue.targetHost,                   forKey: Key.targetHost.rawValue)
            defaults.set(newValue.ipPreference.rawValue,        forKey: Key.ipPreference.rawValue)
            defaults.set(Int(newValue.intervalSeconds * 1000),  forKey: Key.intervalMs.rawValue)
            defaults.set(Int(newValue.timeoutSeconds  * 1000),  forKey: Key.timeoutMs.rawValue)
            defaults.set(newValue.payloadBytes,                 forKey: Key.payloadBytes.rawValue)
        }
    }

    public var thresholds: ThresholdConfig {
        get {
            ThresholdConfig(
                latencyWarnMs:    defaults.double(forKey: Key.latencyWarnMs.rawValue),
                failureDebounce:  defaults.integer(forKey: Key.failureDebounce.rawValue),
                recoveryDebounce: defaults.integer(forKey: Key.recoveryDebounce.rawValue),
                rollingWindow:    defaults.integer(forKey: Key.rollingWindow.rawValue),
                simpleMode:       defaults.bool(forKey: Key.simpleMode.rawValue)
            )
        }
        set {
            defaults.set(newValue.latencyWarnMs,    forKey: Key.latencyWarnMs.rawValue)
            defaults.set(newValue.failureDebounce,  forKey: Key.failureDebounce.rawValue)
            defaults.set(newValue.recoveryDebounce, forKey: Key.recoveryDebounce.rawValue)
            defaults.set(newValue.rollingWindow,    forKey: Key.rollingWindow.rawValue)
            defaults.set(newValue.simpleMode,       forKey: Key.simpleMode.rawValue)
        }
    }

    public func applyPreset(_ preset: Preset) {
        engineConfig = preset.engine
        thresholds   = preset.thresholds
    }
}
