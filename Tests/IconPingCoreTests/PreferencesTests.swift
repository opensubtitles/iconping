import XCTest
@testable import IconPingCore

final class PreferencesTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testDefaults() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        let cfg = p.engineConfig
        XCTAssertEqual(cfg.targetHost, "1.1.1.1")
        XCTAssertEqual(cfg.intervalSeconds, 1.0)
        XCTAssertEqual(cfg.timeoutSeconds, 2.0)
        XCTAssertEqual(cfg.payloadBytes, 56)

        let th = p.thresholds
        XCTAssertEqual(th.failureDebounce, 2)
        XCTAssertEqual(th.recoveryDebounce, 1)
        XCTAssertEqual(th.latencyWarnMs, 300)
        XCTAssertFalse(th.simpleMode)
    }

    func testApplyPreset_Satellite() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        p.applyPreset(.satellite)
        XCTAssertEqual(p.engineConfig.timeoutSeconds, 5.0)
        XCTAssertEqual(p.thresholds.failureDebounce, 3)
        XCTAssertEqual(p.thresholds.latencyWarnMs, 600)
    }

    func testApplyPreset_Lan() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        p.applyPreset(.lan)
        XCTAssertEqual(p.engineConfig.timeoutSeconds, 1.0)
        XCTAssertEqual(p.thresholds.latencyWarnMs, 80)
    }

    func testRoundTrip() {
        let d = freshDefaults()
        let p = Preferences(defaults: d)
        var cfg = p.engineConfig
        cfg.targetHost = "8.8.8.8"
        cfg.ipPreference = .ipv6
        cfg.intervalSeconds = 0.5
        cfg.timeoutSeconds = 3.0
        cfg.payloadBytes = 128
        p.engineConfig = cfg

        let again = Preferences(defaults: d).engineConfig
        XCTAssertEqual(again.targetHost, "8.8.8.8")
        XCTAssertEqual(again.ipPreference, .ipv6)
        XCTAssertEqual(again.intervalSeconds, 0.5)
        XCTAssertEqual(again.timeoutSeconds, 3.0)
        XCTAssertEqual(again.payloadBytes, 128)
    }
}
