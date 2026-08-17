import XCTest
@testable import WhereAmIPCore

final class RenderJSONTests: XCTestCase {
    func fixedState() -> ExitState {
        ExitState(connectivity: .online,
                  exit: ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone GmbH",
                                 provider: "ipwho.is", fetchedAt: Date(timeIntervalSince1970: 1_755_000_000)),
                  route: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "OpenVPN", hijackRoutePresent: false),
                  privateRelay: .inactive,
                  since: Date(timeIntervalSince1970: 1_755_000_000))
    }
    func testJSONGolden() {
        // Documented, additive API change (IPv6 leak detector, Phase 1): "ipv6Leak" and
        // route."v6IsVPN" are new non-optional fields that always serialize (default
        // false/omitted-when-nil for their Optional siblings "exit6" and
        // route."v6DefaultInterface", both nil in this fixture and so omitted below).
        // Existing consumers reading known keys are unaffected; sortedKeys just inserts the
        // new keys alphabetically among the old ones.
        // Further additive change (DNS support): "dns" is now a non-optional field with
        // default values, inserted alphabetically after "connectivity".
        let expected = #"{"connectivity":"online","dns":{"egressIsIPv6":false,"encryption":"unknown","leak":"unknown","resolvers":[]},"exit":{"city":"Frankfurt","countryCode":"DE","fetchedAt":"2025-08-12T12:00:00Z","ip":"1.2.3.4","org":"Vodafone GmbH","provider":"ipwho.is"},"ipv6Leak":false,"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"utun4","hijackRoutePresent":false,"isVPN":true,"v6IsVPN":false,"vpnName":"OpenVPN"},"since":"2025-08-12T12:00:00Z"}"#
        XCTAssertEqual(StateRenderer.json(fixedState()), expected)
    }
    func testJSONGoldenWithIPv6Leak() {
        // Same additive change, now with exit6/v6DefaultInterface populated and a confirmed
        // leak — exercises the full new-field set together, not just their zero values.
        // Further additive change (DNS support): "dns" is now included with default values.
        var s = fixedState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "US", city: "Ashburn", org: "Comcast",
                           provider: "ipwho.is", fetchedAt: Date(timeIntervalSince1970: 1_755_000_000))
        s.route.v6DefaultInterface = "en0"
        s.route.vpnName = "PureVPN"
        s.ipv6Leak = true
        let expected = #"{"connectivity":"online","dns":{"egressIsIPv6":false,"encryption":"unknown","leak":"unknown","resolvers":[]},"exit":{"city":"Frankfurt","countryCode":"DE","fetchedAt":"2025-08-12T12:00:00Z","ip":"1.2.3.4","org":"Vodafone GmbH","provider":"ipwho.is"},"exit6":{"city":"Ashburn","countryCode":"US","fetchedAt":"2025-08-12T12:00:00Z","ip":"2001:db8::1","org":"Comcast","provider":"ipwho.is"},"ipv6Leak":true,"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"utun4","hijackRoutePresent":false,"isVPN":true,"v6DefaultInterface":"en0","v6IsVPN":false,"vpnName":"PureVPN"},"since":"2025-08-12T12:00:00Z"}"#
        XCTAssertEqual(StateRenderer.json(s), expected)
    }
    func testHumanContainsEssentials() {
        let h = StateRenderer.human(fixedState())
        XCTAssertTrue(h.contains("🇩🇪"))
        XCTAssertTrue(h.contains("1.2.3.4"))
        XCTAssertTrue(h.contains("OpenVPN"))
        XCTAssertTrue(h.contains("utun4"))
    }
    func testHumanEndsWithVersionFooter() {
        let h = StateRenderer.human(fixedState())
        XCTAssertTrue(h.hasSuffix("whereamip v\(whereamipVersion)"))
    }
    func testJSONWithAppVersionAddsKeyAdditively() {
        // Documented, additive API change: passing appVersion adds a single
        // top-level "appVersion" key; every other key is byte-identical to the
        // no-appVersion golden above (sortedKeys just inserts it alphabetically).
        let json = StateRenderer.json(fixedState(), appVersion: "9.9.9")
        XCTAssertTrue(json.contains(#""appVersion":"9.9.9""#))
        // Still valid, still every prior key present.
        let obj = try! JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(obj["appVersion"] as? String, "9.9.9")
        XCTAssertEqual(obj["connectivity"] as? String, "online")
        XCTAssertNotNil(obj["exit"])
    }
    func testJSONWithoutAppVersionOmitsKey() {
        XCTAssertFalse(StateRenderer.json(fixedState()).contains("appVersion"))
    }
    func testHumanShowsLeakLineWhenConfirmed() {
        var s = fixedState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "US", city: "Ashburn", org: "Comcast",
                           provider: "ipwho.is", fetchedAt: Date(timeIntervalSince1970: 1_755_000_000))
        s.ipv6Leak = true
        let h = StateRenderer.human(s)
        XCTAssertTrue(h.contains("⚠️ IPv6 leak"))
        XCTAssertTrue(h.contains("Comcast"))
        XCTAssertTrue(h.contains("US"))
        // leak line supersedes the plain split pair in CLI output
        XCTAssertFalse(h.contains("IPv4:"))
        XCTAssertFalse(h.contains("IPv6:"))
    }
    func testHumanShowsSplitPairWhenDifferingWithoutLeak() {
        var s = fixedState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "US", city: "Ashburn", org: "Comcast",
                           provider: "ipwho.is", fetchedAt: Date(timeIntervalSince1970: 1_755_000_000))
        s.ipv6Leak = false
        let h = StateRenderer.human(s)
        XCTAssertTrue(h.contains("IPv4: 1.2.3.4"))
        XCTAssertTrue(h.contains("IPv6: 2001:db8::1"))
        XCTAssertFalse(h.contains("⚠️ IPv6 leak"))
    }

    func testHumanShowsLinkKindInRouteLine() {
        var s = fixedState()
        s.route = RouteInfo(defaultInterface: "en0", isVPN: false, vpnName: nil,
                            hijackRoutePresent: false, linkKind: "Wi-Fi", linkName: "Wi-Fi")
        let h = StateRenderer.human(s)
        XCTAssertTrue(h.contains("route: Wi-Fi (en0)"))
    }

    func testHumanShowsIPv6LineWhenCountriesMatch() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.exit6 = ExitInfo(ip: "2a00::1", countryCode: "CZ", provider: "t", fetchedAt: Date())
        XCTAssertTrue(StateRenderer.human(state).contains("IPv6: 2a00::1"))
    }

    func testHumanOmitsIPv6LineWhenNoV6Measurement() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        XCTAssertFalse(StateRenderer.human(state).contains("IPv6:"))
    }

    func testHumanShowsDNSLine() {
        var state = ExitState(connectivity: .online)
        state.dns.resolvers = [DNSResolver(address: "9.9.9.9", isIPv6: false)]
        XCTAssertTrue(StateRenderer.human(state).contains("dns: 9.9.9.9"))
    }
    // Field bug: DNSConfigReader.parse dedups by (address, interface), so the same address can
    // appear multiple times (global + per-service entries). The "+N" count must reflect unique
    // addresses, not raw resolver-entry count.
    func testHumanDNSCountReflectsUniqueAddressesNotRawEntryCount() {
        var state = ExitState(connectivity: .online)
        let addresses = ["192.168.178.1", "fd00::1", "2001:db8::1", "2001:db8::2"]
        let interfaces: [String?] = [nil, "en0", "utun4"]
        state.dns.resolvers = addresses.flatMap { addr in
            interfaces.map { iface in DNSResolver(address: addr, isIPv6: addr.contains(":"), interface: iface) }
        }
        XCTAssertEqual(state.dns.resolvers.count, 12)
        XCTAssertTrue(StateRenderer.human(state).contains("dns: 192.168.178.1 +3"))
    }
    func testHumanDNSOmitsCountWhenOnlyOneUniqueAddress() {
        var state = ExitState(connectivity: .online)
        state.dns.resolvers = [DNSResolver(address: "9.9.9.9", isIPv6: false),
                               DNSResolver(address: "9.9.9.9", isIPv6: false, interface: "en0"),
                               DNSResolver(address: "9.9.9.9", isIPv6: false, interface: "utun4")]
        let line = StateRenderer.human(state).split(separator: "\n").first { $0.hasPrefix("dns: ") }
        XCTAssertEqual(line, "dns: 9.9.9.9")
    }
    func testHumanShowsDNSLeakConfirmedLine() {
        var state = ExitState(connectivity: .online)
        state.dns.leak = .confirmed
        state.dns.egressIP = "203.0.113.7"
        let h = StateRenderer.human(state)
        XCTAssertTrue(h.contains("⚠️ DNS leak: queries answered via 203.0.113.7"))
    }
    func testHumanShowsDNSLeakConfirmedLineEvenWithoutResolvers() {
        var state = ExitState(connectivity: .online)
        XCTAssertTrue(state.dns.resolvers.isEmpty)
        state.dns.leak = .confirmed
        state.dns.egressIP = "203.0.113.7"
        let h = StateRenderer.human(state)
        XCTAssertTrue(h.contains("⚠️ DNS leak: queries answered via 203.0.113.7"))
    }
    func testHumanShowsDNSLeakSuspectedLine() {
        var state = ExitState(connectivity: .online)
        state.dns.leak = .suspected
        let h = StateRenderer.human(state)
        XCTAssertTrue(h.contains("DNS leak suspected — verifying…"))
    }
    func testHumanOmitsDNSLeakLineWhenNoneOrUnknown() {
        var noneState = ExitState(connectivity: .online)
        noneState.dns.leak = .none
        XCTAssertFalse(StateRenderer.human(noneState).contains("DNS leak"))

        var unknownState = ExitState(connectivity: .online)
        unknownState.dns.leak = .unknown
        XCTAssertFalse(StateRenderer.human(unknownState).contains("DNS leak"))
    }
}
