import XCTest
@testable import IconPingCore

final class StatsAggregatorTests: XCTestCase {

    private func s(_ seq: UInt16, rtt: Double?) -> Sample {
        Sample(
            seq: seq, sentAt: Date(),
            rttSeconds: rtt.map { $0 / 1000.0 },
            status: rtt == nil ? .lost : .received,
            resolvedAddress: nil,
            ipVersion: .ipv4
        )
    }

    func testEmptySnapshot() {
        let agg = StatsAggregator(windowCapacity: 10)
        let snap = agg.snapshot()
        XCTAssertNil(snap.rttAvgMs)
        XCTAssertEqual(snap.lossPercent, 0)
        XCTAssertEqual(snap.windowSize, 0)
    }

    func testMinAvgMax() {
        var agg = StatsAggregator(windowCapacity: 10)
        agg.ingest(s(1, rtt: 10), state: .up)
        agg.ingest(s(2, rtt: 30), state: .up)
        agg.ingest(s(3, rtt: 50), state: .up)
        let snap = agg.snapshot()
        XCTAssertEqual(snap.rttMinMs, 10)
        XCTAssertEqual(snap.rttMaxMs, 50)
        XCTAssertEqual(snap.rttAvgMs!, 30, accuracy: 0.001)
        XCTAssertEqual(snap.lossPercent, 0)
    }

    func testJitterAsMeanAbsoluteDeviation() {
        var agg = StatsAggregator(windowCapacity: 10)
        agg.ingest(s(1, rtt: 10), state: .up)
        agg.ingest(s(2, rtt: 20), state: .up)
        agg.ingest(s(3, rtt: 30), state: .up)
        // diffs: |20-10|=10, |30-20|=10  -> mean = 10
        let snap = agg.snapshot()
        XCTAssertEqual(snap.jitterMs!, 10, accuracy: 0.001)
    }

    func testLossPercentage() {
        var agg = StatsAggregator(windowCapacity: 10)
        agg.ingest(s(1, rtt: 10), state: .up)
        agg.ingest(s(2, rtt: nil), state: .down)
        agg.ingest(s(3, rtt: nil), state: .down)
        agg.ingest(s(4, rtt: 20), state: .up)
        let snap = agg.snapshot()
        XCTAssertEqual(snap.lossPercent, 50)
        XCTAssertEqual(snap.sent, 4)
        XCTAssertEqual(snap.received, 2)
        XCTAssertEqual(snap.lost, 2)
    }

    func testRollingEviction() {
        var agg = StatsAggregator(windowCapacity: 3)
        agg.ingest(s(1, rtt: 100), state: .up)
        agg.ingest(s(2, rtt: 110), state: .up)
        agg.ingest(s(3, rtt: 120), state: .up)
        agg.ingest(s(4, rtt: 130), state: .up)
        let snap = agg.snapshot()
        XCTAssertEqual(snap.windowSize, 3)
        XCTAssertEqual(snap.rttMinMs, 110)
        XCTAssertEqual(snap.rttMaxMs, 130)
    }

    func testUptimePercent() {
        var agg = StatsAggregator(windowCapacity: 10)
        agg.ingest(s(1, rtt: 10), state: .up)
        agg.ingest(s(2, rtt: 20), state: .up)
        agg.ingest(s(3, rtt: nil), state: .down)
        agg.ingest(s(4, rtt: nil), state: .down)
        let snap = agg.snapshot()
        XCTAssertEqual(snap.uptimePercent, 50, accuracy: 0.001)
    }
}
