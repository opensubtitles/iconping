import XCTest
@testable import IconPingCore

final class SpeedTestResultTests: XCTestCase {

    private func make(mbps: Double, error: String? = nil) -> SpeedTestResult {
        SpeedTestResult(
            mbps: mbps,
            bytesReceived: Int(mbps * 1_000_000 / 8 * 8),  // 8s of bandwidth
            durationSeconds: 8.0,
            serverHost: "speed.cloudflare.com",
            errorDescription: error
        )
    }

    func testExcellent_AtBoundary() {
        XCTAssertEqual(make(mbps: 100).verdict, .excellent)
        XCTAssertEqual(make(mbps: 500).verdict, .excellent)
    }

    func testGood() {
        XCTAssertEqual(make(mbps: 50).verdict, .good)
        XCTAssertEqual(make(mbps: 25).verdict, .good, "25 Mbps is the inclusive lower bound")
        XCTAssertEqual(make(mbps: 99.9).verdict, .good)
    }

    func testFair() {
        XCTAssertEqual(make(mbps: 10).verdict, .fair)
        XCTAssertEqual(make(mbps: 5).verdict, .fair, "5 Mbps is the inclusive lower bound")
        XCTAssertEqual(make(mbps: 24.9).verdict, .fair)
    }

    func testPoor() {
        XCTAssertEqual(make(mbps: 2).verdict, .poor)
        XCTAssertEqual(make(mbps: 4.99).verdict, .poor)
    }

    func testBrokenOnSubMbps() {
        XCTAssertEqual(make(mbps: 0.5).verdict, .broken)
        XCTAssertEqual(make(mbps: 0).verdict, .broken)
    }

    func testBrokenOnError() {
        XCTAssertEqual(make(mbps: 50, error: "timeout").verdict, .broken,
                       "any error short-circuits to broken regardless of Mbps")
    }

    func testMegabytesReceivedComputation() {
        let r = SpeedTestResult(mbps: 80, bytesReceived: 10_485_760,  // exactly 10 MiB
                                durationSeconds: 1.0,
                                serverHost: "x", errorDescription: nil)
        XCTAssertEqual(r.megabytesReceived, 10.0, accuracy: 0.001)
    }
}
