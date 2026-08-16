import XCTest
@testable import WhereAmIPCore

final class DNSLeakDetectorTests: XCTestCase {
    let vpn4 = RouteInfo(defaultInterface: "utun13", isVPN: true, vpnName: "PureVPN",
                         hijackRoutePresent: false, v6DefaultInterface: "en0", v6IsVPN: false)
    let noVPN = RouteInfo(defaultInterface: "en0", isVPN: false)
    func exitInfo(_ ip: String) -> ExitInfo { ExitInfo(ip: ip, provider: "t", fetchedAt: Date()) }

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
}
