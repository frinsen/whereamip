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
        // Wave B (binding design change): a second consecutive mismatch confirms ONLY when it
        // carries positive egress-attribution evidence (ASN or org actually resolved and failed
        // to match the tunnel operator) — plain IP inequality with zero attribution data is no
        // longer sufficient on its own. See testAttributionAbsentNeverEscalatesSuspectedToConfirmed
        // below for the no-attribution case this test used to (incorrectly, pre-Wave-B) cover.
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected,
                                              egressASN: 99999), .confirmed)
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
        let exit = exitInfo("1.2.3.4")
        let suspected = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                               exit6: nil, route: vpn4, previous: .none)
        XCTAssertEqual(suspected, .suspected)
        let stillSuspected = DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exit,
                                                    exit6: nil, route: vpn4, previous: suspected)
        XCTAssertEqual(stillSuspected, .suspected, "no ASN/org attribution at all must never confirm on ignorance")
    }
    func testNilEverythingPreservesExistingBehavior() {
        // The pre-existing transition table, re-run with the new params entirely absent. Every
        // row is byte-identical to the original (pre-Wave-B) table EXCEPT the suspected->mismatch
        // row: per the binding design, escalating to .confirmed now requires positive egress-
        // attribution evidence, which nil-everything by definition never carries — that row
        // correctly stays .suspected instead of advancing to .confirmed (see
        // testAttributionAbsentNeverEscalatesSuspectedToConfirmed for the dedicated case, and
        // testSecondConsecutiveMismatchConfirms above for the same transition WITH attribution).
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("9.9.9.9", false), exit4: exitInfo("9.9.9.9"),
                                              exit6: nil, route: noVPN, previous: .confirmed), .none)
        XCTAssertEqual(DNSLeakDetector.decide(egress: nil, exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .unknown)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("1.2.3.4", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .none)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .none), .suspected)
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .suspected), .suspected,
                       "Wave B: no attribution at all -> never escalates on ignorance")
        XCTAssertEqual(DNSLeakDetector.decide(egress: ("203.0.113.7", false), exit4: exitInfo("1.2.3.4"),
                                              exit6: nil, route: vpn4, previous: .confirmed), .confirmed)
    }
    func testSameOperatorHelperASN() {
        XCTAssertTrue(DNSLeakDetector.sameOperator(egressASN: 100, egressOrg: nil, egressProvider: nil,
                                                    exit: exitInfo("1.2.3.4", asn: 100)))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: 100, egressOrg: nil, egressProvider: nil,
                                                     exit: exitInfo("1.2.3.4", asn: 200)))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: nil, egressProvider: nil,
                                                     exit: nil))
    }
    func testSameOperatorHelperOrgNormalization() {
        XCTAssertTrue(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: " PureVPN   Ltd ",
                                                    egressProvider: "ipwho.is",
                                                    exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "purevpn ltd")))
        XCTAssertFalse(DNSLeakDetector.sameOperator(egressASN: nil, egressOrg: "PureVPN",
                                                     egressProvider: "ipwho.is",
                                                     exit: exitInfo("1.2.3.4", provider: "ipwho.is", org: "PureVPN S.A.")))
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
