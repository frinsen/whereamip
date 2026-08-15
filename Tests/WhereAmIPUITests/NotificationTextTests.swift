import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

final class NotificationTextTests: XCTestCase {
    func testCountryChanged() {
        let t = NotificationText.text(for: .countryChanged(from: "DE", to: "NL", vpnName: "OpenVPN"))!
        XCTAssertEqual(t.title, "Exit changed: 🇩🇪 → 🇳🇱")
        XCTAssertTrue(t.body.contains("OpenVPN"))
    }
    func testConnectivityLostPlainVsHijack() {
        XCTAssertTrue(NotificationText.text(for: .connectivityLost(hijackSuspected: false))!.body.contains("probes failing"))
        XCTAssertTrue(NotificationText.text(for: .connectivityLost(hijackSuspected: true))!.body.contains("hijack"))
    }
    func testLeak() {
        XCTAssertTrue(NotificationText.text(for: .leakSuspected(org: "Vodafone"))!.body.contains("Vodafone"))
    }
    func testRouteChangeAloneIsSilent() {
        XCTAssertNil(NotificationText.text(for: .vpnRouteChanged(vpnName: "Tailscale", interface: "utun0")))
    }
    func testIPv6Leak() {
        let t = NotificationText.text(for: .ipv6Leak(country: "DE", org: "Deutsche Telekom"))!
        XCTAssertEqual(t.title, "⚠️ IPv6 leak detected")
        XCTAssertTrue(t.body.contains("Deutsche Telekom"))
        XCTAssertTrue(t.body.contains("only tunnels IPv4"))
    }
    func testIPv6LeakFallsBackToYourISP() {
        let t = NotificationText.text(for: .ipv6Leak(country: nil, org: nil))!
        XCTAssertTrue(t.body.contains("your ISP"))
    }
}
