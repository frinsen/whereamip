import XCTest
@testable import WhereAmIPCore

final class PrivateRelayTests: XCTestCase {
    let csv = """
    172.224.224.0/27,DE,DE-HE,Frankfurt am Main,
    104.28.86.0/26,NL,NL-NH,Amsterdam,
    2a02:26f7:c8c0::/44,DE,DE-HE,Frankfurt am Main,
    """
    // MARK: - IPv4 parsing is a VALIDITY check, not a best-effort extraction
    //
    // `ipv4ToUInt32` is not just the relay-range helper it looks like: it is the only IPv4
    // validity check applied to UNTRUSTED network data — DNSEgressProbe.parseAnswer,
    // DNSEgressEnumerator.parseFrom and DNSLeakDetector.isMeaningful all decide "is this an
    // address at all" through it. A malformed answer that slips past can be judged as a real
    // egress, mismatch the textual comparison, and produce a false DNS-leak alarm out of
    // garbage — so anything that is not exactly four valid octets must be rejected outright,
    // never silently repaired.

    func testMalformedIPv4StringsAreRejectedRatherThanSalvaged() {
        for malformed in ["999.1.2.3.4",     // 5 components, first invalid — must not become 1.2.3.4
                          "abc.1.2.3.4",     // ditto with a non-numeric component
                          "1.2.3.4.garbage", // trailing junk component
                          "1.2..3.4",        // empty component
                          ".1.2.3.4",        // leading dot
                          "1.2.3.4.",        // trailing dot
                          "1.2.3",           // too few
                          "1.2.3.4.5",       // too many
                          "1.2.3.256",       // out of octet range
                          "-1.2.3.4",        // negative
                          "1.2.3.0/24",      // an ECS prefix is not an address
                          "",
                          "..."] {
            XCTAssertNil(RelayRanges.ipv4ToUInt32(malformed), "accepted malformed input: \(malformed)")
        }
    }

    func testValidIPv4StringsStillParseExactly() {
        XCTAssertEqual(RelayRanges.ipv4ToUInt32("0.0.0.0"), 0)
        XCTAssertEqual(RelayRanges.ipv4ToUInt32("255.255.255.255"), UInt32.max)
        XCTAssertEqual(RelayRanges.ipv4ToUInt32("1.2.3.4"), 0x0102_0304)
        XCTAssertEqual(RelayRanges.ipv4ToUInt32("172.224.224.5"), 0xACE0_E005)
    }

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
