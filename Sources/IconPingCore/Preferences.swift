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

        // appearance / runtime presence
        case showLatencyText        = "ui.showLatencyText"
        case flashOnChange          = "ui.flashOnChange"
        case showInDock             = "ui.showInDock"
        case showMenuBar            = "ui.showMenuBar"
        case openDashboardOnLaunch  = "ui.openDashboardOnLaunch"

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
            Key.showLatencyText.rawValue:        false,
            Key.flashOnChange.rawValue:          false,
            Key.showInDock.rawValue:             true,
            Key.showMenuBar.rawValue:            true,
            Key.openDashboardOnLaunch.rawValue:  true,
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
                targetHost:      Preferences.sanitizeTargetHost(defaults.string(forKey: Key.targetHost.rawValue)),
                ipPreference:    IPVersionPreference(rawValue: defaults.string(forKey: Key.ipPreference.rawValue) ?? "auto") ?? .auto,
                intervalSeconds: Preferences.clampInterval(Double(defaults.integer(forKey: Key.intervalMs.rawValue)) / 1000.0),
                timeoutSeconds:  Preferences.clampTimeout(Double(defaults.integer(forKey: Key.timeoutMs.rawValue)) / 1000.0),
                payloadBytes:    Preferences.clampPayload(defaults.integer(forKey: Key.payloadBytes.rawValue))
            )
        }
        set {
            defaults.set(Preferences.sanitizeTargetHost(newValue.targetHost), forKey: Key.targetHost.rawValue)
            defaults.set(newValue.ipPreference.rawValue,        forKey: Key.ipPreference.rawValue)
            defaults.set(Int(Preferences.clampInterval(newValue.intervalSeconds) * 1000),
                         forKey: Key.intervalMs.rawValue)
            defaults.set(Int(Preferences.clampTimeout(newValue.timeoutSeconds) * 1000),
                         forKey: Key.timeoutMs.rawValue)
            defaults.set(Preferences.clampPayload(newValue.payloadBytes),
                         forKey: Key.payloadBytes.rawValue)
        }
    }

    /// Strict hostname / IP-literal validation. Returns a sanitized string, or
    /// "1.1.1.1" if the input is empty / malformed / contains illegal chars.
    /// Designed so corrupt UserDefaults (or a fat-fingered user) can never feed
    /// garbage into the engine.
    public static func sanitizeTargetHost(_ raw: String?) -> String {
        guard let raw else { return "1.1.1.1" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidTargetHost(trimmed) ? trimmed : "1.1.1.1"
    }

    /// True iff the candidate is a syntactically-valid hostname or IP literal.
    /// Does NOT verify that the host resolves — that's the engine's job at runtime.
    public static func isValidTargetHost(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, candidate.count <= 253 else { return false }
        // IPv6: contains ':' — let getaddrinfo decide details, just sanity-check chars.
        if candidate.contains(":") {
            let v6Allowed = Set("0123456789abcdefABCDEF:.")
            return candidate.allSatisfy { v6Allowed.contains($0) } && candidate.count >= 2
        }
        // IPv4 or hostname: must be dot-separated labels, each label 1..63, made of
        // letters / digits / hyphen, not starting or ending with hyphen.
        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            if label.first == "-" || label.last == "-" { return false }
            let labelAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
            if !label.allSatisfy({ labelAllowed.contains($0) }) { return false }
        }
        // Reject lonely-dot edge cases like "." or "..": at least one non-empty label exists already
        // because we omitEmpty=false above and would have failed.
        return true
    }

    public var thresholds: ThresholdConfig {
        get {
            ThresholdConfig(
                latencyWarnMs:    Preferences.clampLatencyWarn(defaults.double(forKey: Key.latencyWarnMs.rawValue)),
                failureDebounce:  Preferences.clampDebounce(defaults.integer(forKey: Key.failureDebounce.rawValue)),
                recoveryDebounce: Preferences.clampDebounce(defaults.integer(forKey: Key.recoveryDebounce.rawValue)),
                rollingWindow:    Preferences.clampWindow(defaults.integer(forKey: Key.rollingWindow.rawValue)),
                simpleMode:       defaults.bool(forKey: Key.simpleMode.rawValue)
            )
        }
        set {
            defaults.set(Preferences.clampLatencyWarn(newValue.latencyWarnMs),
                         forKey: Key.latencyWarnMs.rawValue)
            defaults.set(Preferences.clampDebounce(newValue.failureDebounce),
                         forKey: Key.failureDebounce.rawValue)
            defaults.set(Preferences.clampDebounce(newValue.recoveryDebounce),
                         forKey: Key.recoveryDebounce.rawValue)
            defaults.set(Preferences.clampWindow(newValue.rollingWindow),
                         forKey: Key.rollingWindow.rawValue)
            defaults.set(newValue.simpleMode,       forKey: Key.simpleMode.rawValue)
        }
    }

    public func applyPreset(_ preset: Preset) {
        engineConfig = preset.engine
        thresholds   = preset.thresholds
    }

    /// Wipe every IconPing-owned key + the language override. Defaults from
    /// `registerDefaults()` then apply on the next read.
    public func resetToDefaults() {
        for key in Key.allKnown {
            defaults.removeObject(forKey: key.rawValue)
        }
        defaults.removeObject(forKey: "iconping.langOverrideEnabled")
        registerDefaults()
    }

    // MARK: - Defensive clamping (so corrupt defaults can never break the engine)

    public static let intervalRange: ClosedRange<Double> = 0.05...600
    public static let timeoutRange:  ClosedRange<Double> = 0.1...600
    public static let payloadRange:  ClosedRange<Int>    = 0...1452
    public static let latencyWarnRange: ClosedRange<Double> = 1...60_000
    public static let debounceRange: ClosedRange<Int>    = 1...100
    public static let windowRange:   ClosedRange<Int>    = 5...86_400
    public static let throttleRange: ClosedRange<Int>    = 1...86_400

    public static func clampInterval(_ v: Double)    -> Double { clampD(v, range: intervalRange,    fallback: 1.0)  }
    public static func clampTimeout(_ v: Double)     -> Double { clampD(v, range: timeoutRange,     fallback: 2.0)  }
    public static func clampPayload(_ v: Int)        -> Int    { clampI(v, range: payloadRange,     fallback: 56)   }
    public static func clampLatencyWarn(_ v: Double) -> Double { clampD(v, range: latencyWarnRange, fallback: 300)  }
    public static func clampDebounce(_ v: Int)       -> Int    { clampI(v, range: debounceRange,    fallback: 2)    }
    public static func clampWindow(_ v: Int)         -> Int    { clampI(v, range: windowRange,      fallback: 60)   }
    public static func clampThrottle(_ v: Int)       -> Int    { clampI(v, range: throttleRange,    fallback: 60)   }

    private static func clampD(_ v: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        return min(max(v, range.lowerBound), range.upperBound)
    }
    private static func clampI(_ v: Int, range: ClosedRange<Int>, fallback: Int) -> Int {
        if v < range.lowerBound { return range.lowerBound }
        if v > range.upperBound { return range.upperBound }
        return v
    }
}

extension Preferences.Key {
    /// All keys IconPing owns — used by resetToDefaults.
    public static let allKnown: [Preferences.Key] = [
        .targetHost, .ipPreference, .intervalMs, .timeoutMs, .payloadBytes,
        .latencyWarnMs, .failureDebounce, .recoveryDebounce, .rollingWindow, .simpleMode,
        .showLatencyText, .flashOnChange, .showInDock, .showMenuBar, .openDashboardOnLaunch,
        .notifyOnDown, .notifyOnUp, .notifyThrottle, .notifySound, .openAtLogin
    ]
}
