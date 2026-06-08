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
        let r = sm.ingest(sample: sample(seq: 1, success: true))
        XCTAssertEqual(r.state, .up)
        XCTAssertNotNil(r.transition)
    }

    func testDownRequiresNConsecutiveLosses() {
        var sm = StateMachine(thresholds: ThresholdConfig(failureDebounce: 3))
        _ = sm.ingest(sample: sample(seq: 1, success: true))
        XCTAssertEqual(sm.state, .up)

        let r1 = sm.ingest(sample: sample(seq: 2, success: false))
        XCTAssertEqual(r1.state, .up, "1 loss should not flip")
        let r2 = sm.ingest(sample: sample(seq: 3, success: false))
        XCTAssertEqual(r2.state, .up, "2 losses with debounce=3 should not flip")
        let r3 = sm.ingest(sample: sample(seq: 4, success: false))
        XCTAssertEqual(r3.state, .down, "3 losses should flip to down")
        XCTAssertNotNil(r3.transition)
    }

    func testSingleLossDoesNotFlipDefault() {
        var sm = StateMachine() // failureDebounce=2
        _ = sm.ingest(sample: sample(seq: 1, success: true))
        let r = sm.ingest(sample: sample(seq: 2, success: false))
        XCTAssertEqual(r.state, .up)
    }

    func testRecoveryAfterDown() {
        var sm = StateMachine(thresholds: ThresholdConfig(failureDebounce: 2, recoveryDebounce: 2))
        _ = sm.ingest(sample: sample(seq: 1, success: false))
        _ = sm.ingest(sample: sample(seq: 2, success: false))
        XCTAssertEqual(sm.state, .down)

        let r1 = sm.ingest(sample: sample(seq: 3, success: true))
        XCTAssertEqual(r1.state, .down, "1 success with recovery=2 should not flip")
        let r2 = sm.ingest(sample: sample(seq: 4, success: true))
        XCTAssertEqual(r2.state, .up)
    }

    func testSlowOnFirstSampleAboveThreshold() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 200))
        let r = sm.ingest(sample: sample(seq: 1, success: true, rttMs: 250))
        XCTAssertEqual(r.state, .slow)
    }

    func testFastSampleStaysUp() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 200))
        let r = sm.ingest(sample: sample(seq: 1, success: true, rttMs: 50))
        XCTAssertEqual(r.state, .up)
    }

    /// A single slow ping (e.g. cold-start) should not lock the icon to .slow.
    /// The state should bounce back to .up after three fast samples in a row.
    func testColdStartSlowRecoversQuickly() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 200))
        let r1 = sm.ingest(sample: sample(seq: 1, success: true, rttMs: 800))
        XCTAssertEqual(r1.state, .slow, "cold start ping above threshold lands in .slow")
        _ = sm.ingest(sample: sample(seq: 2, success: true, rttMs: 50))
        _ = sm.ingest(sample: sample(seq: 3, success: true, rttMs: 50))
        let r4 = sm.ingest(sample: sample(seq: 4, success: true, rttMs: 50))
        XCTAssertEqual(r4.state, .up, "3 consecutive fast samples flip back to .up")
    }

    /// Once in .up, a single jittery sample shouldn't visibly flip to .slow.
    func testJitterDoesNotFlipFromUp() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 200))
        _ = sm.ingest(sample: sample(seq: 1, success: true, rttMs: 50))
        let r2 = sm.ingest(sample: sample(seq: 2, success: true, rttMs: 800))
        XCTAssertEqual(r2.state, .up, "single jitter spike doesn't flip from .up")
        let r3 = sm.ingest(sample: sample(seq: 3, success: true, rttMs: 800))
        XCTAssertEqual(r3.state, .up, "two slow samples still under debounce 3")
        let r4 = sm.ingest(sample: sample(seq: 4, success: true, rttMs: 800))
        XCTAssertEqual(r4.state, .slow, "three consecutive slow samples flip to .slow")
    }

    func testSimpleModeCollapsesSlow() {
        var sm = StateMachine(thresholds: ThresholdConfig(latencyWarnMs: 100, simpleMode: true))
        let r = sm.ingest(sample: sample(seq: 1, success: true, rttMs: 800))
        XCTAssertEqual(r.state, .up)
    }
}
