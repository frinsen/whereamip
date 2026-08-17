import XCTest
@testable import WhereAmIPCore

final class DNSLeakDetectorTests: XCTestCase {
    let vpn4 = RouteInfo(defaultInterface: "utun13", isVPN: true, vpnName: "PureVPN",
                         hijackRoutePresent: false, v6DefaultInterface: "en0", v6IsVPN: false)
    let noVPN = RouteInfo(defaultInterface: "en0", isVPN: false)
    func exitInfo(_ ip: String, provider: String = "t", org: String? = nil, asn: Int? = nil) -> ExitInfo {
        ExitInfo(ip: ip, org: org, provider: provider, fetchedAt: Date(), asn: asn)
    }

    func testNoVPNAnywhereIsNoneAndClearsConfirmed() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("9.9.9.9", false), exit4: exitInfo("9.9.9.9"),
                                              exit6: nil, route: noVPN, previous: .confirmed), .none)
    }
    func testNoMeasurementIsUnknown() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: nil, exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
    }
    func testNoMeasurementPreservesConfirmed() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: nil, exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .confirmed), .confirmed)
    }
    func testTunnelMatchedEgressIsNoneAndRecovers() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("1.2.3.4", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .none)
    }
    func testMismatchFirstSightIsSuspected() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .suspected)
    }
    func testSecondConsecutiveMismatchConfirms() {
        // Unchanged from pre-Wave-B: the exit here carries no attribution at all (no asn/org),
        // so per the adjudicated gate a rescue was never even possible — plain escalation
        // proceeds exactly as before. (The "hold at .suspected" gate only applies when the
        // judged exit itself HAS attribution but the egress lookup came back empty — see
        // testAttributionAbsentNeverEscalatesSuspectedToConfirmed.)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .confirmed)
    }
    func testConfirmedMismatchStaysConfirmed() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .confirmed), .confirmed)
    }
    func testCrossStackV6EscapeIsSuspected() {
        // v4 tunneled, DNS answered over native v6 → DNS escaped the tunnel. THE PureVPN case.
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("2a00:1450::5", true), exit4: exitInfo("1.2.3.4"),
                                              exit6: exitInfo("2a00:1450::5"), route: vpn4,
                                              previous: .none), .suspected)
    }
    func testCrossStackMismatchEscalatesRegardlessOfAttribution() {
        // IMPORTANT 4: cross-stack mismatches (egress's own stack was never tunneled at all —
        // routing alone already proves the leak) never reach the org/ASN rescue path, so the
        // "hold at suspected" gate must never apply there either. Escalates exactly as
        // pre-Wave-B, even with zero attribution on both sides.
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("2a00:1450::5", true), exit4: exitInfo("1.2.3.4"),
                                              exit6: exitInfo("2a00:1450::5"), route: vpn4,
                                              previous: .suspected), .confirmed)
    }
    func testVPNStackButNoFreshExitIsUnknown() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: nil,
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
    }
    func testECSPrefixMatchIsNone() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("1.2.3.0/24", false), exit4: exitInfo("1.2.3.77"),
                                              exit6: nil, route: vpn4, previous: .none), .none)
    }
    func testIPMatchesHelpers() {
        XCTAssertTrue(DNSLeakDetector.ipMatches("1.2.3.77", prefixOrIP: "1.2.3.0/24"))
        XCTAssertFalse(DNSLeakDetector.ipMatches("1.2.4.1", prefixOrIP: "1.2.3.0/24"))
        XCTAssertTrue(DNSLeakDetector.ipMatches("2a00:1450::5", prefixOrIP: "2a00:1450::5"))
        XCTAssertTrue(DNSLeakDetector.ipMatches("2a00:1450:0:0:0:0:0:5", prefixOrIP: "2a00:1450::5"))
    }
    func testZeroScopePrefixIsNoMeasurement() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("0.0.0.0/0", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .confirmed), .confirmed)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("0.0.0.0/0", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
    }
    func testUnparseableEgressIsNoMeasurement() {
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("1.2.3.0/999", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("not-an-ip", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
    }
    // MARK: - Org/ASN rescue (Wave B)

    func testASNMatchRescuesToNone() {
        // Mismatched IPs, but the resolver's egress ASN equals the tunnel exit's ASN — same
        // operator's own DNS, not a leak.
        let exit = exitInfo("1.2.3.4", asn: 12345)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .none,
                                              egressASN: 12345), .none)
    }
    func testASNMismatchWithNoOrgEscalatesOnSecondConsecutiveMismatch() {
        let exit = exitInfo("1.2.3.4", asn: 12345)
        let first = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                           exit6: nil, route: vpn4, previous: .none,
                                           egressASN: 99999)
        XCTAssertEqual(first, .suspected)
        let second = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                            exit6: nil, route: vpn4, previous: first,
                                            egressASN: 99999)
        XCTAssertEqual(second, .confirmed, "ASN attribution present and mismatched is positive evidence")
    }
    func testOrgExactMatchSameProviderRescues() {
        let exit = exitInfo("1.2.3.4", provider: "ipwho.is", org: "PureVPN Ltd")
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .none,
                                              egressOrg: "  PureVPN   Ltd  ", egressProvider: "ipwho.is"), .none,
                      "exact org match (case-insensitive, whitespace-collapsed) from the SAME provider rescues")
    }
    func testOrgMatchDifferentProviderDoesNotRescue() {
        let exit = exitInfo("1.2.3.4", provider: "ipwho.is", org: "PureVPN Ltd")
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .none,
                                              egressOrg: "PureVPN Ltd", egressProvider: "ipapi.co"), .suspected,
                      "org strings from DIFFERENT geo providers are not comparable — no rescue")
    }
    func testOrgContainmentIsNotEqualityDoesNotRescue() {
        // Conservative by design: containment ("PureVPN" is a substring of "PureVPN S.A.")
        // must NOT count as a match — only exact normalized equality rescues.
        let exit = exitInfo("1.2.3.4", provider: "ipwho.is", org: "PureVPN S.A.")
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .none,
                                              egressOrg: "PureVPN", egressProvider: "ipwho.is"), .suspected)
    }
    func testAttributionAbsentNeverEscalatesSuspectedToConfirmed() {
        // The judged exit DOES carry attribution (asn: 12345) — a rescue was theoretically
        // possible — but the egress lookup came back with nothing at all (both nil). That's
        // "unevaluable", not "compared and mismatched": hold at .suspected forever rather than
        // confirm on ignorance.
        let exit = exitInfo("1.2.3.4", asn: 12345)
        let suspected = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                               exit6: nil, route: vpn4, previous: .none)
        XCTAssertEqual(suspected, .suspected)
        let stillSuspected = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                                    exit6: nil, route: vpn4, previous: suspected)
        XCTAssertEqual(stillSuspected, .suspected,
                       "exit has attribution but egress lookup found none — rescue was possible but unevaluable")
    }
    func testNilEverythingPreservesExistingBehavior() {
        // The full pre-existing transition table, re-run with the new params entirely absent —
        // byte-identical to the original (pre-Wave-B) table. True precisely because the "hold"
        // gate requires the JUDGED EXIT to carry attribution; none of these exits do, so a
        // rescue was never possible and plain escalation always proceeds.
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("9.9.9.9", false), exit4: exitInfo("9.9.9.9"),
                                              exit6: nil, route: noVPN, previous: .confirmed), .none)
        XCTAssertEqual(DNSLeakDetector.decide(egress: nil, exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("1.2.3.4", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .none)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .suspected)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .confirmed)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .confirmed), .confirmed)
    }
    func testSameOperatorHelperASN() {
        XCTAssertTrue(DNSLeakDetector.sameOperator(egressASN: 100, egressOrg: nil, egressProvider: nil,
                                                    exit: exitInfo("1.2.3.4", asn: 100)))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: 100, egressOrg: nil, egressProvider: nil,
                                                     exit: exitInfo("1.2.3.4", asn: 200)))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: nil, egressProvider: nil,
                                                     exit: exitInfo("1.2.3.4")))
    }
    func testSameOperatorHelperOrgNormalization() {
        XCTAssertTrue(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: " PureVPN   Ltd ",
                                                    egressProvider: "ipwho.is",
                                                    exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "purevpn ltd")))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: "PureVPN",
                                                     egressProvider: "ipwho.is",
                                                     exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "PureVPN S.A.")))
    }

    // MARK: - Sentinel-value regressions (external review round 2, live-verified)

    func testZeroASNSentinelNeverRescuesOrClearsConfirmed() {
        // Live-verified: ipwho.is returns asn: 0 for IPs it can't attribute — including the
        // exact ECS-network-address shape Monitor feeds it (e.g. "1.2.3.0" from "1.2.3.0/24").
        // 0 == 0 must NEVER count as an ASN match, or a genuinely confirmed alarm could be
        // silently cleared just because both sides happened to be unattributed.
        let exit = exitInfo("1.2.3.4", asn: 0)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .confirmed,
                                              egressASN: 0), .confirmed,
                       "asn:0 on both sides must not rescue a mismatch or clear .confirmed")
    }
    func testEmptyOrgSentinelNeverRescues() {
        // "" == "" trivially satisfies Swift string equality — must be excluded the same way.
        let exit = exitInfo("1.2.3.4", provider: "ipwho.is", org: "")
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                              exit6: nil, route: vpn4, previous: .confirmed,
                                              egressOrg: "", egressProvider: "ipwho.is"), .confirmed,
                       "empty org strings on both sides must not rescue or clear .confirmed")
    }
    func testSameOperatorRejectsZeroASN() {
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: 0, egressOrg: nil, egressProvider: nil,
                                                     exit: exitInfo("1.2.3.4", asn: 0)))
    }
    func testSameOperatorRejectsEmptyOrg() {
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: "",
                                                     egressProvider: "ipwho.is",
                                                     exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "")))
    }
    func testSameOperatorRejectsWhitespaceOnlyOrg() {
        // Normalizes to empty — must be treated as absent, same as a literal "".
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: "   ",
                                                     egressProvider: "ipwho.is",
                                                     exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "  ")))
    }

    func testIsMeaningfulHelpers() {
        XCTAssertTrue(DNSLeakDetector.isMeaningful("1.2.3.4"))
        XCTAssertTrue(DNSLeakDetector.isMeaningful("2a00::1"))
        XCTAssertTrue(DNSLeakDetector.isMeaningful("1.2.3.0/24"))
        XCTAssertTrue(DNSLeakDetector.isMeaningful("2a00::/32"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful("0.0.0.0/0"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful("::/0"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful("1.2.3.0/999"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful("1.2.3.0/abc"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful("hello"))
        XCTAssertFalse(DNSLeakDetector.isMeaningful(""))
    }
}
