import XCTest
@testable import WhereAmIPCore

final class RouteInspectorTests: XCTestCase {
    func testTunnelClassification() {
        XCTAssertTrue(RouteInspector.isTunnelInterface("utun4"))
        XCTAssertTrue(RouteInspector.isTunnelInterface("ppp0"))
        XCTAssertTrue(RouteInspector.isTunnelInterface("ipsec0"))
        XCTAssertFalse(RouteInspector.isTunnelInterface("en0"))
        XCTAssertFalse(RouteInspector.isTunnelInterface("lo0"))
    }
    func testLiveDefaultRouteSmokeTest() {
        // On any online dev machine this returns an interface; offline it may be nil — both fine, must not crash.
        if let r = RouteInspector.defaultRouteInterface() {
            XCTAssertFalse(r.interface.isEmpty)
            XCTAssertFalse(r.localAddress.isEmpty)
        }
    }
    func testSnapshotComposes() {
        let info = RouteInspector.snapshot()
        if let iface = info.defaultInterface {
            XCTAssertEqual(info.isVPN, RouteInspector.isTunnelInterface(iface))
        } else {
            XCTAssertFalse(info.isVPN)
        }
    }
}
