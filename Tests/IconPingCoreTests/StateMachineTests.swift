import XCTest
@testable import IconPingCore

final class StateMachineTests: XCTestCase {

    private func sample(seq: UInt16, success: Bool, rttMs: Double? = 50) -> Sample {
        Sample(
            seq: seq,
            sentAt: Date(),
            rttSeconds: success ? (rttMs ?? 50) / 1000.0 : nil,
            status: success ? .received : .lost,
            resolvedAddress: "1.1.1.1",
            ipVersion: .ipv4
        )
    }

    func testStartsUnknownThenUp() {
        var sm = StateMachine()
        XCTAssertEqual(sm.state, .unknown)
        let r = sm.ingest(sample: sample(seq: 1, success: true), rollingAvgMs: 40)
        XCTAssertEqual(r.state, .up)
        XCTAssertNotNil(r.transition)
    }

    func testDownRequiresNConsecutiveLosses() {
        var sm = StateMachine(thresholds: ThresholdConfig(failureDebounce: 3))
        _ = sm.ingest(sample: sample(seq: 1, success: true), rollingAvgMs: 30)
        XCTAssertEqual(sm.state, .up)

        let r1 = sm.ingest(sample: sample(seq: 2, success: false), rollingAvgMs: 30)
        XCTAssertEqual(r1.state, .up, "1 loss should not flip")
        let r2 = sm.ingest(sample: sample(seq: 3, success: false), rollingAvgMs: 30)
        XCTAssertEqual(r2.state, .up, "2 losses with debounce=3 should not flip")
        let r3 = sm.ingest(sample: sample(seq: 4, success: false), rollingAvgMs: 30)
        XCTAssertEqual(r3.state, .down, "3 losses should flip to down")
        XCTAssertNotNil(r3.transition)
    }

    func testSingleLossDoesNotFlipDefault() {
        var sm = StateMachine() // failureDebounce=2
        _ = sm.ingest(sample: sample(seq: 1, success: true), rollingAvgMs: 30)
        let r = sm.ingest(sample: sample(seq: 2, success: false), rollingAvgMs: 30)
        XCTAssertEqual(r.state, .up)
    }

    func testRecoveryAfterDown() {
        var sm = StateMachine(thresholds: ThresholdConfig(failureDebounce: 2, recoveryDebounce: 2))
        _ = sm.ingest(sample: sample(seq: 1, success: false), rollingAvgMs: nil)
        _ = sm.ingest(sample: sample(seq: 2, success: false), rollingAvgMs: nil)
        XCTAssertEqual(sm.state, .down)

        let r1 = sm.ingest(sample: sample(seq: 3, success: true), rollingAvgMs: 50)
        XCTAssertEqual(r1.state, .down, "1 success with recovery=2 should not flip")
        let r2 = sm.ingest(sample: sample(seq: 4, success: true), rollingAvgMs: 50)
        XCTAssertEqual(r2.state, .up)
    }

    func testSlowClassification() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 200))
        let r = sm.ingest(sample: sample(seq: 1, success: true), rollingAvgMs: 250)
        XCTAssertEqual(r.state, .slow)
    }

    func testSimpleModeCollapsesSlow() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 100, simpleMode: true))
        let r = sm.ingest(sample: sample(seq: 1, success: true), rollingAvgMs: 800)
        XCTAssertEqual(r.state, .up)
    }
}
