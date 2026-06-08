import XCTest
@testable import IconPingCore

final class SpeedTestResultTests: XCTestCase {

    private func phase(mbps: Double, error: String? = nil) -> PhaseResult {
        PhaseResult(
            mbps: mbps,
            bytes: Int(mbps * 1_000_000),
            durationSeconds: 8.0,
            errorDescription: error
        )
    }

    private func make(download: Double, upload: Double = 10,
                      downloadError: String? = nil) -> SpeedTestResult {
        SpeedTestResult(
            download: phase(mbps: download, error: downloadError),
            upload: phase(mbps: upload),
            serverHost: "speed.cloudflare.com"
        )
    }

    func testExcellent_AtBoundary() {
        XCTAssertEqual(make(download: 100).verdict, .excellent)
        XCTAssertEqual(make(download: 500).verdict, .excellent)
    }

    func testGood() {
        XCTAssertEqual(make(download: 50).verdict, .good)
        XCTAssertEqual(make(download: 25).verdict, .good, "25 Mbps is inclusive lower bound")
        XCTAssertEqual(make(download: 99.9).verdict, .good)
    }

    func testFair() {
        XCTAssertEqual(make(download: 10).verdict, .fair)
        XCTAssertEqual(make(download: 5).verdict, .fair)
        XCTAssertEqual(make(download: 24.9).verdict, .fair)
    }

    func testPoor() {
        XCTAssertEqual(make(download: 2).verdict, .poor)
        XCTAssertEqual(make(download: 4.99).verdict, .poor)
    }

    func testBrokenOnSubMbps() {
        XCTAssertEqual(make(download: 0.5).verdict, .broken)
        XCTAssertEqual(make(download: 0).verdict, .broken)
    }

    func testBrokenOnDownloadError() {
        XCTAssertEqual(make(download: 50, downloadError: "timeout").verdict, .broken,
                       "download error short-circuits to broken regardless of Mbps")
    }

    func testUploadErrorDoesNotAffectVerdict() {
        // High download with broken upload should still verdict on download.
        let r = SpeedTestResult(
            download: phase(mbps: 150),
            upload: phase(mbps: 0, error: "Cancelled"),
            serverHost: "x"
        )
        XCTAssertEqual(r.verdict, .excellent)
    }

    func testPhaseMegabytes() {
        let p = PhaseResult(mbps: 80, bytes: 10_485_760, durationSeconds: 1.0)
        XCTAssertEqual(p.megabytes, 10.0, accuracy: 0.001)
    }
}
