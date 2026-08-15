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
    func testLiveDefaultRouteV6SmokeTest() {
        // Same nil-safety contract as the v4 smoke test above: on a dual-stack online dev
        // machine this returns an interface; on a v4-only network (or offline) nil is
        // expected and fine — must never crash either way.
        if let r = RouteInspector.defaultRouteInterface6() {
            XCTAssertFalse(r.interface.isEmpty)
            XCTAssertFalse(r.localAddress.isEmpty)
        }
    }
    func testSnapshotComposesV6() {
        let info = RouteInspector.snapshot()
        if let iface6 = info.v6DefaultInterface {
            XCTAssertEqual(info.v6IsVPN, RouteInspector.isTunnelInterface(iface6))
        } else {
            XCTAssertFalse(info.v6IsVPN)
        }
    }
}
