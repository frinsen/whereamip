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
        let expected = #"{"connectivity":"online","exit":{"city":"Frankfurt","countryCode":"DE","fetchedAt":"2025-08-12T12:00:00Z","ip":"1.2.3.4","org":"Vodafone GmbH","provider":"ipwho.is"},"privateRelay":{"status":"inactive"},"route":{"defaultInterface":"utun4","hijackRoutePresent":false,"isVPN":true,"vpnName":"OpenVPN"},"since":"2025-08-12T12:00:00Z"}"#
        XCTAssertEqual(StateRenderer.json(fixedState()), expected)
    }
    func testHumanContainsEssentials() {
        let h = StateRenderer.human(fixedState())
        XCTAssertTrue(h.contains("🇩🇪"))
        XCTAssertTrue(h.contains("1.2.3.4"))
        XCTAssertTrue(h.contains("OpenVPN"))
        XCTAssertTrue(h.contains("utun4"))
    }
}
