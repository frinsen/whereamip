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

    // MARK: - parses: telling "same version" apart from "no version at all"
    //
    // isNewer answers false in both directions for equal versions AND for unparseable
    // ones, which is fine for the update check (neither is an update) but not for the
    // single-instance guard, where "we cannot read it" and "it is our version" must lead
    // to opposite outcomes.

    func testParsesAcceptsTheShapesIsNewerCompares() {
        XCTAssertTrue(SemVer.parses("0.6"))
        XCTAssertTrue(SemVer.parses("v0.6"))
        XCTAssertTrue(SemVer.parses("0.6.1"))
        XCTAssertTrue(SemVer.parses("0.6-beta.1"))
        XCTAssertTrue(SemVer.parses("0"))
    }

    func testParsesRejectsAnythingWithoutADottedNumericCore() {
        XCTAssertFalse(SemVer.parses("garbage"))
        XCTAssertFalse(SemVer.parses(""))
        XCTAssertFalse(SemVer.parses("v"))
        XCTAssertFalse(SemVer.parses("0.6.x"))
        XCTAssertFalse(SemVer.parses("-1.0"))
    }
}
