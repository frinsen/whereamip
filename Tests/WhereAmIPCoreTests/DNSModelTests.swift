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

    // MARK: - C4: DNSInfo.egressOrg

    func testOldDNSJSONWithoutEgressOrgKeyStillDecodes() throws {
        // dns-shaped JSON predating egressOrg (Wave C) — no "egressOrg" key at all. Must decode
        // with a nil default rather than throw.
        let old = """
        {"connectivity":"online","exit":{"ip":"1.2.3.4","provider":"test","fetchedAt":"2026-08-16T10:00:00Z"},"ipv6Leak":false,"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"en0","hijackRoutePresent":false,"isVPN":false},"since":"2026-08-16T10:00:00Z","dns":{"resolvers":[],"encryption":"unknown","egressIsIPv6":false,"leak":"confirmed","egressIP":"203.0.113.7"}}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let state = try dec.decode(ExitState.self, from: Data(old.utf8))
        XCTAssertNil(state.dns.egressOrg)
        XCTAssertEqual(state.dns.leak, .confirmed)
        XCTAssertEqual(state.dns.egressIP, "203.0.113.7")
    }

    // MARK: - egressResolvers (DNS egress enumeration)

    func testOldDNSJSONWithoutEgressResolversKeyStillDecodes() throws {
        // dns-shaped JSON predating the enumeration round — no "egressResolvers" key at all.
        // Must decode as an empty list rather than throw, exactly like egressOrg above.
        let old = """
        {"connectivity":"online","exit":{"ip":"1.2.3.4","provider":"test","fetchedAt":"2026-08-16T10:00:00Z"},"ipv6Leak":false,"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"en0","hijackRoutePresent":false,"isVPN":false},"since":"2026-08-16T10:00:00Z","dns":{"resolvers":[],"encryption":"unknown","egressIsIPv6":false,"leak":"confirmed","egressIP":"203.0.113.7","egressOrg":"Cloudflare, Inc."}}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let state = try dec.decode(ExitState.self, from: Data(old.utf8))
        XCTAssertEqual(state.dns.egressResolvers, [])
        XCTAssertEqual(state.dns.egressIP, "203.0.113.7")
        XCTAssertEqual(state.dns.egressOrg, "Cloudflare, Inc.")
    }

    func testDNSInfoWithEgressResolversRoundTrips() throws {
        var s = ExitState()
        s.dns = DNSInfo(resolvers: [], encryption: .plaintext, egressIP: "74.80.89.244",
                        egressIsIPv6: false, measuredAt: Date(timeIntervalSince1970: 1_000_000),
                        leak: .none, egressOrg: "WoodyNet, Inc.",
                        egressResolvers: [EgressResolver(ip: "74.80.89.244", port: 39071,
                                                         operatorName: "WoodyNet, Inc.",
                                                         location: "Berlin, State of Berlin, DE",
                                                         transport: "TLS"),
                                          EgressResolver(ip: "2620:171:57:f003:9999::244")])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(ExitState.self, from: enc.encode(s))
        XCTAssertEqual(back.dns, s.dns)
        XCTAssertEqual(back.dns.egressResolvers.map(\.ip), ["74.80.89.244", "2620:171:57:f003:9999::244"])
    }

    func testDNSInfoWithEgressOrgRoundTrips() throws {
        var s = ExitState()
        s.dns = DNSInfo(resolvers: [], encryption: .doh, egressIP: "203.0.113.7", egressIsIPv6: false,
                        measuredAt: Date(timeIntervalSince1970: 1_000_000), leak: .confirmed,
                        egressOrg: "Cloudflare, Inc.")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(ExitState.self, from: enc.encode(s))
        XCTAssertEqual(back.dns, s.dns)
        XCTAssertEqual(back.dns.egressOrg, "Cloudflare, Inc.")
    }
}
