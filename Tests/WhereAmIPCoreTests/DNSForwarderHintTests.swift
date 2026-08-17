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

    // MARK: - router-local: on-link prefixes

    // This machine's real shape (2026-08-17): a Fritz!Box hands out its own GLOBAL address from
    // the ISP's delegated /64 as a resolver, so "is it private" is the wrong question — "is it
    // on a segment I'm directly attached to" is the right one.
    let hostPrefixes = [InterfacePrefix(address: "192.168.178.154", prefixLength: 24),
                        InterfacePrefix(address: "fd6b:908e:1000:0:1886:5871:b861:d17a", prefixLength: 64),
                        InterfacePrefix(address: "2001:9e8:a4d:d200:f17b:627:5a58:4ca8", prefixLength: 64)]

    func testGlobalIPv6ResolverInsideAHostPrefixIsRouterLocal() {
        XCTAssertTrue(DNSForwarderHint.isRouterLocal("2001:9e8:a4d:d200:3e37:12ff:fef5:5abc",
                                                     localPrefixes: hostPrefixes))
    }
    func testGlobalAddressOutsideEveryHostPrefixIsNotRouterLocal() {
        // Neighbouring /64s and unrelated global addresses only — an RFC1918 address would pass
        // on the private table alone and prove nothing about the prefix path.
        for a in ["2620:fe::fe", "2001:9e8:a4d:d201:3e37:12ff:fef5:5abc", "9.9.9.9", "203.0.113.9"] {
            XCTAssertFalse(DNSForwarderHint.isRouterLocal(a, localPrefixes: hostPrefixes), "\(a)")
        }
    }
    func testIPv4SubnetMatchingHandlesNonByteAlignedMasks() {
        // Public addresses throughout: the whole point is the mask arithmetic, which the
        // private-range table would otherwise short-circuit. 203.0.116.9/20 spans
        // 203.0.112.0–203.0.127.255.
        let twenty = [InterfacePrefix(address: "203.0.116.9", prefixLength: 20)]
        XCTAssertTrue(DNSForwarderHint.isRouterLocal("203.0.127.254", localPrefixes: twenty))
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("203.0.128.1", localPrefixes: twenty))

        // A /30 link net — only the three sibling addresses may qualify.
        let thirty = [InterfacePrefix(address: "203.0.113.5", prefixLength: 30)]
        XCTAssertTrue(DNSForwarderHint.isRouterLocal("203.0.113.6", localPrefixes: thirty))
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("203.0.113.9", localPrefixes: thirty))
    }
    func testEmptyPrefixListFallsBackToPrivateRangeBehavior() {
        XCTAssertTrue(DNSForwarderHint.isRouterLocal("192.168.178.1", localPrefixes: []))
        XCTAssertTrue(DNSForwarderHint.isRouterLocal("fd00::1", localPrefixes: []))
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("2001:9e8:a4d:d200:3e37:12ff:fef5:5abc", localPrefixes: []))
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("9.9.9.9", localPrefixes: []))
    }
    func testZeroLengthPrefixNeverMatches() {
        // Defensive: a /0 from a malformed snapshot would otherwise make every address "local"
        // and turn the hint into a claim about resolvers this Mac talks to directly.
        let bogus = [InterfacePrefix(address: "0.0.0.0", prefixLength: 0),
                     InterfacePrefix(address: "::", prefixLength: 0)]
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("9.9.9.9", localPrefixes: bogus))
        XCTAssertFalse(DNSForwarderHint.isRouterLocal("2620:fe::fe", localPrefixes: bogus))
    }

    // MARK: - router-local: the same box in a rotated prefix

    // Field case on this machine: macOS still lists the router under a PREVIOUS delegated
    // prefix (ISPs rotate them) that the Mac no longer holds an address in. Same box — same
    // interface identifier as the ULA entry, which is router-local beyond doubt.
    func staleAndCurrent() -> [DNSResolver] {
        [DNSResolver(address: "192.168.178.1", isIPv6: false),
         DNSResolver(address: "fd6b:908e:1000:0:3e37:12ff:fef5:5abc", isIPv6: true),
         DNSResolver(address: "2001:9e8:a54:d400:3e37:12ff:fef5:5abc", isIPv6: true),   // stale prefix
         DNSResolver(address: "2001:9e8:a4d:d200:3e37:12ff:fef5:5abc", isIPv6: true)]
    }
    func testResolverInARotatedPrefixIsAttributedToTheSameRouter() {
        XCTAssertEqual(DNSForwarderHint.provider(configured: staleAndCurrent(), egress: quad9Egress(),
                                                 localPrefixes: hostPrefixes), "Quad9")
    }
    func testTheSameBoxRuleNeedsAnAnchorItCannotBootstrapItself() {
        // Strip every resolver that is router-local on its own: three addresses sharing an
        // interface identifier prove nothing if none of them is anchored to this machine.
        let orphans = [DNSResolver(address: "2001:9e8:a54:d400:3e37:12ff:fef5:5abc", isIPv6: true),
                       DNSResolver(address: "2001:db8:1:1:3e37:12ff:fef5:5abc", isIPv6: true)]
        XCTAssertNil(DNSForwarderHint.provider(configured: orphans, egress: quad9Egress(),
                                               localPrefixes: hostPrefixes))
    }
    func testADifferentBoxInAForeignPrefixStillSuppressesTheHint() {
        let foreign = staleAndCurrent() + [DNSResolver(address: "2620:fe::fe", isIPv6: true)]
        XCTAssertNil(DNSForwarderHint.provider(configured: foreign, egress: quad9Egress(),
                                               localPrefixes: hostPrefixes))
    }
    func testInterfaceIdentifierIsTheLowSixtyFourBits() {
        XCTAssertEqual(DNSForwarderHint.interfaceIdentifier("2001:db8::1"),
                       DNSForwarderHint.interfaceIdentifier("fd00:1:2:3::1"))
        XCTAssertNotEqual(DNSForwarderHint.interfaceIdentifier("2001:db8::1"),
                          DNSForwarderHint.interfaceIdentifier("2001:db8::2"))
        XCTAssertNil(DNSForwarderHint.interfaceIdentifier("9.9.9.9"), "IPv4 has no interface identifier")
        XCTAssertNil(DNSForwarderHint.interfaceIdentifier("garbage"))
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
        XCTAssertEqual(DNSForwarderHint.provider(configured: routerResolvers(), egress: quad9Egress(),
                                                 localPrefixes: []), "Quad9")
    }
    func testAnyPublicConfiguredResolverSuppressesTheHint() {
        // The Mac talks to Quad9 itself here — nothing is being forwarded by a router, so
        // attributing the hop to one would be plain wrong.
        let mixed = routerResolvers() + [DNSResolver(address: "9.9.9.9", isIPv6: false)]
        XCTAssertNil(DNSForwarderHint.provider(configured: mixed, egress: quad9Egress(), localPrefixes: []))
    }
    func testUnattributableEgressSuppressesTheHint() {
        let isp = [EgressResolver(ip: "62.109.121.1", operatorName: "Deutsche Telekom AG")]
        XCTAssertNil(DNSForwarderHint.provider(configured: routerResolvers(), egress: isp, localPrefixes: []))
    }
    func testEmptyInputsSuppressTheHint() {
        XCTAssertNil(DNSForwarderHint.provider(configured: [], egress: quad9Egress(), localPrefixes: []))
        XCTAssertNil(DNSForwarderHint.provider(configured: routerResolvers(), egress: [], localPrefixes: []))
    }
    func testFirstAttributableEgressWins() {
        let pool = [EgressResolver(ip: "62.109.121.1", operatorName: "Deutsche Telekom AG"),
                    EgressResolver(ip: "74.80.89.244", operatorName: "WoodyNet, Inc.")]
        XCTAssertEqual(DNSForwarderHint.provider(configured: routerResolvers(), egress: pool,
                                                 localPrefixes: []), "Quad9")
    }
}
