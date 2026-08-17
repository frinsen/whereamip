import XCTest
@testable import WhereAmIPCore

final class DNSModelTests: XCTestCase {
    func testOldJSONWithoutDNSKeyStillDecodes() throws {
        // v0.3-shaped ExitState JSON: no "dns" key. Must decode with defaults.
        let old = """
        {"connectivity":"online","exit":{"ip":"1.2.3.4","provider":"test","fetchedAt":"2026-08-16T10:00:00Z"},"ipv6Leak":false,"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"en0","hijackRoutePresent":false,"isVPN":false},"since":"2026-08-16T10:00:00Z"}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let state = try dec.decode(ExitState.self, from: Data(old.utf8))
        XCTAssertEqual(state.dns, DNSInfo())
        XCTAssertEqual(state.dns.leak, .unknown)
        // Wave A additive fields (connection-kind display): absent in this pre-existing JSON,
        // must decode as nil rather than throw.
        XCTAssertNil(state.route.linkKind)
        XCTAssertNil(state.route.linkName)
    }

    func testDNSInfoRoundTrips() throws {
        var s = ExitState()
        s.dns = DNSInfo(resolvers: [DNSResolver(address: "10.8.0.1", isIPv6: false, interface: "utun13")],
                        encryption: .doh, egressIP: "203.0.113.7", egressIsIPv6: false,
                        measuredAt: Date(timeIntervalSince1970: 1_000_000), leak: .confirmed)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(ExitState.self, from: enc.encode(s))
        XCTAssertEqual(back.dns, s.dns)
    }

    func testJSONOutputContainsDNSKey() {
        XCTAssertTrue(StateRenderer.json(ExitState()).contains("\"dns\""))
    }
}
