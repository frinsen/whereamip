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
}
