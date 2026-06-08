import XCTest
@testable import IconPingCore

final class QuickTestResultTests: XCTestCase {

    private func make(sent: Int, received: Int, avg: Double?, jitter: Double? = 5) -> QuickTestResult {
        QuickTestResult(
            sent: sent, received: received,
            minMs: avg.map { $0 - 5 }, avgMs: avg, maxMs: avg.map { $0 + 5 },
            jitterMs: jitter, durationSeconds: 6.0
        )
    }

    func testExcellent() {
        let r = make(sent: 30, received: 30, avg: 20, jitter: 4)
        XCTAssertEqual(r.verdict, .excellent)
        XCTAssertEqual(r.lossPercent, 0)
    }

    func testGood() {
        let r = make(sent: 30, received: 30, avg: 100, jitter: 30)
        XCTAssertEqual(r.verdict, .good)
    }

    func testFair() {
        let r = make(sent: 30, received: 29, avg: 220, jitter: 60) // 3.3% loss
        XCTAssertEqual(r.verdict, .fair)
    }

    func testPoorOnHighLatency() {
        let r = make(sent: 30, received: 30, avg: 450, jitter: 30)
        XCTAssertEqual(r.verdict, .poor)
    }

    func testPoorOnLoss() {
        let r = make(sent: 30, received: 27, avg: 50, jitter: 5) // 10% loss → poor
        XCTAssertEqual(r.verdict, .poor)
    }

    func testBrokenOnZeroReceived() {
        let r = make(sent: 30, received: 0, avg: nil, jitter: nil)
        XCTAssertEqual(r.verdict, .broken)
        XCTAssertEqual(r.lossPercent, 100)
    }

    func testJitterPushesGoodToFair() {
        // 0% loss, low latency, but jitter above 50 — excellent/good require jitter <50.
        // Loss <5 and avg <300 → fair.
        let r = make(sent: 30, received: 30, avg: 120, jitter: 80)
        XCTAssertEqual(r.verdict, .fair)
    }

    func testZeroSent() {
        let r = QuickTestResult(sent: 0, received: 0, minMs: nil, avgMs: nil,
                                maxMs: nil, jitterMs: nil, durationSeconds: 0)
        XCTAssertEqual(r.lossPercent, 0)
    }
}
