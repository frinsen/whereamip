import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

final class NotificationTextTests: XCTestCase {
    func testCountryChanged() {
        let t = NotificationText.text(for: .countryChanged(from: "DE", to: "NL", vpnName: "OpenVPN"))!
        XCTAssertEqual(t.title, L10n.string(.notificationCountryChangedTitle, "🇩🇪", "🇳🇱"))
        XCTAssertTrue(t.body.contains("OpenVPN"))
    }
    func testConnectivityLostPlainVsHijack() {
        XCTAssertEqual(NotificationText.text(for: .connectivityLost(hijackSuspected: false))!.body,
                       L10n.string(.notificationOfflineBody))
        XCTAssertEqual(NotificationText.text(for: .connectivityLost(hijackSuspected: true))!.body,
                       L10n.string(.notificationOfflineBodyHijack))
    }
    func testLeak() {
        XCTAssertTrue(NotificationText.text(for: .leakSuspected(org: "Vodafone"))!.body.contains("Vodafone"))
    }
    func testRouteChangeAloneIsSilent() {
        XCTAssertNil(NotificationText.text(for: .vpnRouteChanged(vpnName: "Tailscale", interface: "utun0")))
    }
    func testIPv6Leak() {
        let t = NotificationText.text(for: .ipv6Leak(country: "DE", org: "Deutsche Telekom"))!
        XCTAssertEqual(t.title, L10n.string(.notificationIPv6Title))
        XCTAssertEqual(t.body, L10n.string(.notificationIPv6Body, "Deutsche Telekom"))
    }
    func testIPv6LeakFallsBackToYourISP() {
        let t = NotificationText.text(for: .ipv6Leak(country: nil, org: nil))!
        XCTAssertEqual(t.body, L10n.string(.notificationIPv6Body, L10n.string(.notificationOrgUnknown)))
    }
    func testDNSLeakNotificationText() {
        let t = NotificationText.text(for: .dnsLeakConfirmed(egressIP: "203.0.113.7", resolver: "192.168.1.1"))
        XCTAssertEqual(t?.title, L10n.string(.notificationDNSTitle))
        XCTAssertTrue(t?.body.contains("203.0.113.7") ?? false)
    }
}
