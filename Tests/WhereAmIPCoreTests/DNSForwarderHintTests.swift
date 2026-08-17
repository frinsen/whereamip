import XCTest
@testable import WhereAmIPCore

final class DNSForwarderHintTests: XCTestCase {
    // MARK: - private-range predicate

    func testPrivateIPv4Ranges() {
        for a in ["10.0.0.1", "10.255.255.254", "172.16.0.1", "172.31.255.254", "192.168.178.1"] {
            XCTAssertTrue(DNSForwarderHint.isPrivate(a), "\(a) is RFC1918")
        }
    }
    func testPublicIPv4IsNotPrivate() {
        // 172.15/172.32 bracket the 172.16/12 block — the classic off-by-one in hand-rolled checks.
        for a in ["9.9.9.9", "1.1.1.1", "172.15.255.255", "172.32.0.1", "193.168.178.1", "8.8.8.8"] {
            XCTAssertFalse(DNSForwarderHint.isPrivate(a), "\(a) is public")
        }
    }
    func testPrivateIPv6Ranges() {
        for a in ["fe80::1", "FE80::1", "fe80:0:0:0:0:0:0:1", "fd00::1", "fdab:cd12::5"] {
            XCTAssertTrue(DNSForwarderHint.isPrivate(a), "\(a) is link-local or ULA")
        }
    }
    func testPublicIPv6IsNotPrivate() {
        for a in ["2001:db8::1", "2620:fe::fe", "::1", "fc00::1"] {
            XCTAssertFalse(DNSForwarderHint.isPrivate(a), "\(a) is not fe80::/10 or fd00::/8")
        }
    }
    func testGarbageIsNotPrivate() {
        XCTAssertFalse(DNSForwarderHint.isPrivate(""))
        XCTAssertFalse(DNSForwarderHint.isPrivate("router.local"))
    }

    // MARK: - provider table

    func testKnownProvidersMatchCaseInsensitivelyBySubstring() {
        XCTAssertEqual(DNSForwarderHint.knownProvider("WoodyNet, Inc."), "Quad9")
        XCTAssertEqual(DNSForwarderHint.knownProvider("Quad9 Foundation"), "Quad9")
        XCTAssertEqual(DNSForwarderHint.knownProvider("CLOUDFLARE, INC."), "Cloudflare")
        XCTAssertEqual(DNSForwarderHint.knownProvider("Google LLC"), "Google Public DNS")
        XCTAssertEqual(DNSForwarderHint.knownProvider("nextdns inc"), "NextDNS")
    }
    func testUnknownOperatorHasNoProvider() {
        XCTAssertNil(DNSForwarderHint.knownProvider("Deutsche Telekom AG"))
        XCTAssertNil(DNSForwarderHint.knownProvider(""))
        XCTAssertNil(DNSForwarderHint.knownProvider(nil))
    }

    // MARK: - the combined rule

    func routerResolvers() -> [DNSResolver] {
        [DNSResolver(address: "192.168.178.1", isIPv6: false),
         DNSResolver(address: "fd00::1", isIPv6: true, interface: "en0")]
    }
    func quad9Egress() -> [EgressResolver] {
        [EgressResolver(ip: "74.80.89.244", operatorName: "WoodyNet, Inc.")]
    }
    func testRouterForwardingToAKnownProviderIsAttributed() {
        XCTAssertEqual(DNSForwarderHint.provider(configured: routerResolvers(), egress: quad9Egress()), "Quad9")
    }
    func testAnyPublicConfiguredResolverSuppressesTheHint() {
        // The Mac talks to Quad9 itself here — nothing is being forwarded by a router, so
        // attributing the hop to one would be plain wrong.
        let mixed = routerResolvers() + [DNSResolver(address: "9.9.9.9", isIPv6: false)]
        XCTAssertNil(DNSForwarderHint.provider(configured: mixed, egress: quad9Egress()))
    }
    func testUnattributableEgressSuppressesTheHint() {
        let isp = [EgressResolver(ip: "62.109.121.1", operatorName: "Deutsche Telekom AG")]
        XCTAssertNil(DNSForwarderHint.provider(configured: routerResolvers(), egress: isp))
    }
    func testEmptyInputsSuppressTheHint() {
        XCTAssertNil(DNSForwarderHint.provider(configured: [], egress: quad9Egress()))
        XCTAssertNil(DNSForwarderHint.provider(configured: routerResolvers(), egress: []))
    }
    func testFirstAttributableEgressWins() {
        let pool = [EgressResolver(ip: "62.109.121.1", operatorName: "Deutsche Telekom AG"),
                    EgressResolver(ip: "74.80.89.244", operatorName: "WoodyNet, Inc.")]
        XCTAssertEqual(DNSForwarderHint.provider(configured: routerResolvers(), egress: pool), "Quad9")
    }
}
