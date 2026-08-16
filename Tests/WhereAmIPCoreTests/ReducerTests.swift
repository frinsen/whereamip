import XCTest
@testable import WhereAmIPCore

final class ReducerTests: XCTestCase {
    func state(_ c: Connectivity, ip: String?, iso: String?, org: String? = nil,
               iface: String? = "en0", vpn: Bool = false, vpnName: String? = nil,
               hijack: Bool = false, relay: PrivateRelay = .inactive,
               ipv6Leak: Bool = false, exit6CC: String? = nil, exit6Org: String? = nil) -> ExitState {
        var s = ExitState(connectivity: c,
                  exit: ip.map { ExitInfo(ip: $0, countryCode: iso, city: nil, org: org, provider: "t", fetchedAt: Date(timeIntervalSince1970: 0)) },
                  route: RouteInfo(defaultInterface: iface, isVPN: vpn, vpnName: vpnName, hijackRoutePresent: hijack),
                  privateRelay: relay, since: Date(timeIntervalSince1970: 0))
        s.ipv6Leak = ipv6Leak
        s.exit6 = exit6CC.map { ExitInfo(ip: "::1", countryCode: $0, org: exit6Org, provider: "t", fetchedAt: Date(timeIntervalSince1970: 0)) }
        return s
    }
    func testCountryChange() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE"),
                                new: state(.online, ip: "2.2.2.2", iso: "NL", iface: "utun4", vpn: true, vpnName: "OpenVPN"))
        XCTAssertTrue(ev.contains(.countryChanged(from: "DE", to: "NL", vpnName: "OpenVPN")))
        XCTAssertFalse(ev.contains(where: { if case .ipChanged = $0 { true } else { false } }))
    }
    func testIPChangeSameCountry() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE", org: "Vodafone"),
                                new: state(.online, ip: "3.3.3.3", iso: "DE", org: "Telekom"))
        XCTAssertEqual(ev, [.ipChanged(country: "DE", fromOrg: "Vodafone", toOrg: "Telekom")])
    }
    func testConnectivityLostWithHijack() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE"),
                                new: state(.offline, ip: "1.1.1.1", iso: "DE", hijack: true))
        XCTAssertTrue(ev.contains(.connectivityLost(hijackSuspected: true)))
    }
    func testRestore() {
        let ev = Reducer.events(old: state(.offline, ip: nil, iso: nil),
                                new: state(.online, ip: "1.1.1.1", iso: "DE", org: "Vodafone"))
        XCTAssertTrue(ev.contains(.connectivityRestored(country: "DE", city: nil, org: "Vodafone")))
    }
    func testCheckingToOnlineIsSilent() {
        XCTAssertEqual(Reducer.events(old: state(.checking, ip: nil, iso: nil),
                                      new: state(.online, ip: "1.1.1.1", iso: "DE", org: nil)), [])
    }
    func testVPNRouteChange() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE"),
                                new: state(.online, ip: "1.1.1.1", iso: "DE", iface: "utun4", vpn: true, vpnName: "Tailscale"))
        XCTAssertTrue(ev.contains(.vpnRouteChanged(vpnName: "Tailscale", interface: "utun4")))
    }
    func testLeakSuspected() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE", org: "Vodafone"),
                                new: state(.online, ip: "1.1.1.1", iso: "DE", org: "Vodafone",
                                           iface: "utun4", vpn: true, vpnName: "OpenVPN"))
        XCTAssertTrue(ev.contains(.leakSuspected(org: "Vodafone")))
    }
    func testRelayToggle() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE"),
                                new: state(.online, ip: "1.1.1.1", iso: "DE",
                                           relay: .active(egressIP: "5.6.7.8", egressCountry: nil)))
        XCTAssertTrue(ev.contains(.privateRelayToggled(active: true)))
        let ev2 = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "DE", relay: .unknown),
                                 new: state(.online, ip: "1.1.1.1", iso: "DE", relay: .inactive))
        XCTAssertFalse(ev2.contains(.privateRelayToggled(active: false)))
    }
    func testNoChangesNoEvents() {
        let s = state(.online, ip: "1.1.1.1", iso: "DE")
        XCTAssertEqual(Reducer.events(old: s, new: s), [])
    }
    func testIPv6LeakFiresOnceOnFalseToTrue() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: false),
                                new: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: true,
                                           exit6CC: "DE", exit6Org: "Telekom"))
        XCTAssertTrue(ev.contains(.ipv6Leak(country: "DE", org: "Telekom")))
    }
    func testIPv6LeakTrueToTrueIsSilent() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: true,
                                           exit6CC: "DE", exit6Org: "Telekom"),
                                new: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: true,
                                           exit6CC: "DE", exit6Org: "Telekom"))
        XCTAssertFalse(ev.contains { if case .ipv6Leak = $0 { return true }; return false })
    }
    func testIPv6LeakTrueToFalseIsSilent() {
        let ev = Reducer.events(old: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: true,
                                           exit6CC: "DE", exit6Org: "Telekom"),
                                new: state(.online, ip: "1.1.1.1", iso: "NL", ipv6Leak: false))
        XCTAssertFalse(ev.contains { if case .ipv6Leak = $0 { return true }; return false })
    }
    func testDNSLeakConfirmedFiresOnlyOnTheEdge() {
        var old = ExitState(); var new = ExitState()
        new.dns.leak = .confirmed
        new.dns.egressIP = "203.0.113.7"
        new.dns.resolvers = [DNSResolver(address: "192.168.1.1", isIPv6: false)]
        XCTAssertTrue(Reducer.events(old: old, new: new)
            .contains(.dnsLeakConfirmed(egressIP: "203.0.113.7", resolver: "192.168.1.1")))
        old.dns.leak = .confirmed   // persisting confirmed → no repeat event
        XCTAssertFalse(Reducer.events(old: old, new: new)
            .contains(.dnsLeakConfirmed(egressIP: "203.0.113.7", resolver: "192.168.1.1")))
    }
    func testSuspectedDoesNotFireEvent() {
        var new = ExitState(); new.dns.leak = .suspected
        XCTAssertTrue(Reducer.events(old: ExitState(), new: new).allSatisfy {
            if case .dnsLeakConfirmed = $0 { return false } else { return true }
        })
    }
}
