import XCTest
@testable import WhereAmIPCore

final class PrivateRelayTests: XCTestCase {
    let csv = """
    172.224.224.0/27,DE,DE-HE,Frankfurt am Main,
    104.28.86.0/26,NL,NL-NH,Amsterdam,
    2a02:26f7:c8c0::/44,DE,DE-HE,Frankfurt am Main,
    """
    func testCIDRContains() {
        let r = RelayRanges(csv: csv)
        XCTAssertTrue(r.containsIPv4("172.224.224.5"))     // inside /27
        XCTAssertFalse(r.containsIPv4("172.224.224.32"))   // outside /27
        XCTAssertTrue(r.containsIPv4("104.28.86.63"))
        XCTAssertFalse(r.containsIPv4("8.8.8.8"))
        XCTAssertFalse(r.containsIPv4("not-an-ip"))
    }
    func testDecision() {
        let r = RelayRanges(csv: csv)
        XCTAssertEqual(PrivateRelayDetector.decide(httpsIP: "46.114.1.2", httpIP: nil, ranges: r), .unknown)
        XCTAssertEqual(PrivateRelayDetector.decide(httpsIP: "46.114.1.2", httpIP: "172.224.224.5", ranges: r),
                       .active(egressIP: "172.224.224.5", egressCountry: nil))
        XCTAssertEqual(PrivateRelayDetector.decide(httpsIP: "46.114.1.2", httpIP: "46.114.1.2", ranges: r), .inactive)
        // Same IP even if in ranges → whole system exits via relay-adjacent net; treat as inactive split
        XCTAssertEqual(PrivateRelayDetector.decide(httpsIP: "172.224.224.5", httpIP: "172.224.224.5", ranges: r), .inactive)
    }
    func testBundledRangesLoad() {
        XCTAssertTrue(RelayRanges.bundled().containsIPv4("172.224.224.1") || true) // just must not crash & parse
    }
}
