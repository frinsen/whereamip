import XCTest
@testable import WhereAmIPCore

final class InstanceArbiterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    private func me(_ version: String?, _ started: Date?) -> InstanceArbiter.Instance {
        InstanceArbiter.Instance(version: version, startedAt: started)
    }

    // MARK: - Version wins, whatever the clock says

    func testNewerOtherMakesUsYieldEvenWhenWeStartedFirst() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.5.5", at(0)), versus: me("0.6", at(100))), .yield)
    }

    func testOlderOtherIsTakenOverEvenWhenItStartedFirst() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(100)), versus: me("0.5.5", at(0))), .takeOver)
    }

    // MARK: - Equal versions: the earlier-started instance wins

    func testEqualVersionsOtherStartedFirstMakesUsYield() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(10)), versus: me("0.6", at(0))), .yield)
    }

    func testEqualVersionsWeStartedFirstSoWeTakeOver() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(0)), versus: me("0.6", at(10))), .takeOver)
    }

    /// A tie to the microsecond cannot be broken; yielding is the half of the pair that
    /// cannot leave two instances killing each other.
    func testEqualVersionsExactStartTieYields() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(0)), versus: me("0.6", at(0))), .yield)
    }

    /// The boot race the guard exists for: two same-version copies launched by two BTM
    /// records, each arbitrating against the other. Exactly one must survive, and it must
    /// be the one that started first.
    func testEqualVersionBootRaceLeavesExactlyOneSurvivor() {
        let first = me("0.6", at(0))
        let second = me("0.6", at(0.4))
        XCTAssertEqual(InstanceArbiter.decide(first, versus: second), .takeOver)
        XCTAssertEqual(InstanceArbiter.decide(second, versus: first), .yield)
    }

    // MARK: - Missing launch dates

    func testEqualVersionsUnknownOtherStartIsTreatedAsStartedLater() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(10)), versus: me("0.6", nil)), .takeOver)
    }

    func testEqualVersionsUnknownOwnStartYieldsToADatedOther() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", nil), versus: me("0.6", at(10))), .yield)
    }

    func testEqualVersionsBothStartsUnknownYields() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", nil), versus: me("0.6", nil)), .yield)
    }

    // MARK: - Unreadable / unparseable versions

    func testUnreadableOtherVersionCountsAsOlder() {
        // Started first AND version unknown: still taken over — a bundle we cannot read a
        // version out of must never displace a healthy one.
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(10)), versus: me(nil, at(0))), .takeOver)
    }

    func testGarbageOtherVersionCountsAsOlder() {
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(10)), versus: me("not-a-version", at(0))), .takeOver)
    }

    func testUnparseableOwnVersionYieldsToAReadableOther() {
        XCTAssertEqual(InstanceArbiter.decide(me("garbage", at(0)), versus: me("0.6", at(10))), .yield)
    }

    func testBothVersionsUnparseableFallsBackToTheStartTimeTiebreak() {
        XCTAssertEqual(InstanceArbiter.decide(me(nil, at(0)), versus: me(nil, at(10))), .takeOver)
        XCTAssertEqual(InstanceArbiter.decide(me(nil, at(10)), versus: me(nil, at(0))), .yield)
    }

    func testPrereleaseOfTheSameCoreIsNotNewerAndFallsToTheTiebreak() {
        // SemVer's rule: "0.6-beta.1" is the same release as "0.6", not a step forward.
        XCTAssertEqual(InstanceArbiter.decide(me("0.6", at(0)), versus: me("0.6-beta.1", at(10))), .takeOver)
    }

    // MARK: - Aggregate verdict over every other instance found

    func testNoOtherInstancesProceeds() {
        XCTAssertEqual(InstanceArbiter.verdict(me("0.6", at(0)), versus: []), .proceed)
    }

    func testASingleOlderOtherIsTakenOver() {
        XCTAssertEqual(InstanceArbiter.verdict(me("0.6", at(10)), versus: [me("0.5.5", at(0))]), .takeOver)
    }

    func testAnyYieldWinsOverATakeOver() {
        // One older copy and one newer copy running at once: we are not the newest, so we
        // leave — terminating the older one on the way out is not ours to do.
        let verdict = InstanceArbiter.verdict(me("0.6", at(10)),
                                              versus: [me("0.5.5", at(0)), me("0.7", at(5))])
        XCTAssertEqual(verdict, .yield)
    }

    func testEveryOtherOlderStillTakesOver() {
        let verdict = InstanceArbiter.verdict(me("0.6", at(10)),
                                              versus: [me("0.5.5", at(0)), me(nil, at(1))])
        XCTAssertEqual(verdict, .takeOver)
    }

    // MARK: - Which running applications count as us

    func testOwnBundleIdentifierIsASibling() {
        XCTAssertTrue(InstanceArbiter.isSibling(bundleIdentifier: "io.github.frinsen.whereamip",
                                                ownIdentifier: "io.github.frinsen.whereamip"))
    }

    /// The field bug: a pre-2026-08-13 dev registration under the old identifier is what
    /// launched the second copy, and it never matches Bundle.main's identifier.
    func testLegacyBundleIdentifierIsASibling() {
        XCTAssertTrue(InstanceArbiter.isSibling(bundleIdentifier: InstanceArbiter.legacyBundleIdentifier,
                                                ownIdentifier: "io.github.frinsen.whereamip"))
        XCTAssertEqual(InstanceArbiter.legacyBundleIdentifier, "io.github.martinfrindt.whereamip")
    }

    func testLegacyIdentifierStillMatchesWhenOurOwnIdentifierIsUnknown() {
        XCTAssertTrue(InstanceArbiter.isSibling(bundleIdentifier: InstanceArbiter.legacyBundleIdentifier,
                                                ownIdentifier: nil))
    }

    func testUnrelatedApplicationsAreNotSiblings() {
        XCTAssertFalse(InstanceArbiter.isSibling(bundleIdentifier: "com.apple.Safari",
                                                 ownIdentifier: "io.github.frinsen.whereamip"))
        XCTAssertFalse(InstanceArbiter.isSibling(bundleIdentifier: nil,
                                                 ownIdentifier: "io.github.frinsen.whereamip"))
        // A prefix match is not a match: never mistake a neighbour for ourselves.
        XCTAssertFalse(InstanceArbiter.isSibling(bundleIdentifier: "io.github.frinsen.whereamip.helper",
                                                 ownIdentifier: "io.github.frinsen.whereamip"))
    }

    func testIdentifierComparisonIsCaseInsensitive() {
        // Launch Services treats bundle identifiers case-insensitively.
        XCTAssertTrue(InstanceArbiter.isSibling(bundleIdentifier: "IO.GitHub.Frinsen.WhereAmIP",
                                                ownIdentifier: "io.github.frinsen.whereamip"))
    }

    func testEmptyOwnIdentifierNeverMatchesEverything() {
        XCTAssertFalse(InstanceArbiter.isSibling(bundleIdentifier: "", ownIdentifier: ""))
    }
}
