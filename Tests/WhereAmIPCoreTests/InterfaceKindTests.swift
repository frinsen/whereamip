import XCTest
@testable import WhereAmIPCore

final class InterfaceKindTests: XCTestCase {
    func testWiFiType() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "IEEE80211", display: "Wi-Fi"), "Wi-Fi")
    }
    func testEthernetWithIPhoneDisplayNameIsTethering() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "Ethernet", display: "iPhone USB"), "iPhone USB")
    }
    func testPlainEthernet() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "Ethernet", display: "USB 10/100/1000 LAN"), "Ethernet")
    }
    func testEthernetWithNilDisplay() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "Ethernet", display: nil), "Ethernet")
    }
    func testBridge() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "Bridge", display: nil), "Bridge")
    }
    func testEmptyTypeIsUnknown() {
        XCTAssertEqual(InterfaceKind.kindLabel(type: "", display: nil), "Unknown")
    }
    func testUnrecognizedTypePassesThrough() {
        // No hardcoded vendor knowledge — an SC type we don't special-case still surfaces
        // something meaningful rather than collapsing to "Unknown".
        XCTAssertEqual(InterfaceKind.kindLabel(type: "PPP", display: nil), "PPP")
    }
    func testLookupReturnsNilForUnknownBSDName() {
        // Live smoke test: a synthetic bsdName that (virtually certainly) doesn't exist on
        // this machine must come back nil, not crash.
        XCTAssertNil(InterfaceKind.lookup(bsdName: "zzz999notreal"))
    }
}
