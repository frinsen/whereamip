import XCTest
@testable import WhereAmIPCore

final class ReducerTests: XCTestCase {
    func state(_ c: Connectivity, ip: String?, iso: String?, org: String? = nil,
               iface: String? = "en0", vpn: Bool = false, vpnName: String? = nil,
               hijack: Bool = false, relay: PrivateRelay = .inactive) -> ExitState {
        ExitState(connectivity: c,
                  exit: ip.map { ExitInfo(ip: $0, countryCode: iso, city: nil, org: org, provider: "t", fetchedAt: Date(timeIntervalSince1970: 0)) },
                  route: RouteInfo(defaultInterface: iface, isVPN: vpn, vpnName: vpnName, hijackRoutePresent: hijack),
                  privateRelay: relay, since: Date(timeIntervalSince1970: 0))
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
}
