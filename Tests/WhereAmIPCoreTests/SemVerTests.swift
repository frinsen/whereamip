import XCTest
@testable import WhereAmIPCore

final class SemVerTests: XCTestCase {
    func testPatchNewer() {
        XCTAssertTrue(SemVer.isNewer("0.3", than: "0.2"))
    }
    func testDoubleDigitMinorBeatsSingleDigit() {
        XCTAssertTrue(SemVer.isNewer("0.10", than: "0.9"))
    }
    func testEqualIsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("0.2", than: "0.2"))
    }
    func testLongerCoreBeatsShorterWhenPrefixMatches() {
        XCTAssertTrue(SemVer.isNewer("0.2.1", than: "0.2"))
    }
    func testLeadingVTolerated() {
        XCTAssertTrue(SemVer.isNewer("v0.3", than: "0.2"))
    }
    func testPrereleaseOfSameCoreIsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("0.3-beta.1", than: "0.3"))
    }
    func testGarbageIsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("garbage", than: "0.2"))
        XCTAssertFalse(SemVer.isNewer("0.3", than: "garbage"))
    }
}
