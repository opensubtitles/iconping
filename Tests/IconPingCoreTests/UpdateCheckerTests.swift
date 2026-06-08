import XCTest
@testable import IconPingCore

final class UpdateCheckerTests: XCTestCase {

    func testSemverParse_basic() {
        let s = UpdateChecker.Semver("1.2.3")!
        XCTAssertEqual(s.major, 1); XCTAssertEqual(s.minor, 2); XCTAssertEqual(s.patch, 3)
    }

    func testSemverParse_vPrefix() {
        let s = UpdateChecker.Semver("v1.0.12")!
        XCTAssertEqual(s.major, 1); XCTAssertEqual(s.minor, 0); XCTAssertEqual(s.patch, 12)
    }

    func testSemverParse_majorMinorOnly() {
        let s = UpdateChecker.Semver("2.5")!
        XCTAssertEqual(s.patch, 0)
    }

    func testSemverParse_invalid() {
        XCTAssertNil(UpdateChecker.Semver(""))
        XCTAssertNil(UpdateChecker.Semver("notaversion"))
        XCTAssertNil(UpdateChecker.Semver("1"))
    }

    func testSemverComparison_patch() {
        XCTAssertLessThan(UpdateChecker.Semver("1.0.0")!, UpdateChecker.Semver("1.0.1")!)
        XCTAssertLessThan(UpdateChecker.Semver("1.0.9")!, UpdateChecker.Semver("1.0.10")!,
                          "patch 10 > 9 numerically, not string-wise")
    }

    func testSemverComparison_minor() {
        XCTAssertLessThan(UpdateChecker.Semver("1.1.0")!, UpdateChecker.Semver("1.2.0")!)
        XCTAssertLessThan(UpdateChecker.Semver("1.9.9")!, UpdateChecker.Semver("1.10.0")!)
    }

    func testSemverComparison_major() {
        XCTAssertLessThan(UpdateChecker.Semver("1.99.99")!, UpdateChecker.Semver("2.0.0")!)
    }

    func testSemverEqual() {
        XCTAssertEqual(UpdateChecker.Semver("1.0.0"), UpdateChecker.Semver("v1.0.0"))
    }
}
