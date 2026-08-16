import XCTest
@testable import WhereAmIPCore

/// Live-state detector tests. NEVER run in the default suite: every test is
/// gated on WHEREAMIP_E2E=1, set only by scripts/e2e/run.sh at defined states.
final class E2ERouteTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testRouteSnapshotMatchesExpectedState() throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        let snap = RouteInspector.snapshot()
        if env["E2E_EXPECT_VPN"] == "1" {
            XCTAssertTrue(snap.isVPN, "expected VPN route, got \(snap.defaultInterface ?? "nil")")
            if let prefix = env["E2E_EXPECT_IFACE_PREFIX"] {
                XCTAssertTrue(snap.defaultInterface?.hasPrefix(prefix) ?? false,
                              "iface \(snap.defaultInterface ?? "nil") lacks prefix \(prefix)")
            }
        } else if env["E2E_EXPECT_VPN"] == "0" {
            XCTAssertFalse(snap.isVPN)
        }
    }

    func testV6AttributionCoherent() throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        let snap = RouteInspector.snapshot()
        if snap.v6IsVPN { XCTAssertNotNil(snap.v6DefaultInterface) }
    }
}
