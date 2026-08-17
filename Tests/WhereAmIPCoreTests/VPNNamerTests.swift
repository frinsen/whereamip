import XCTest
@testable import WhereAmIPCore

final class VPNNamerTests: XCTestCase {
    func testTailscaleByCGNATAddress() {
        XCTAssertEqual(VPNNamer.name(interface: "utun0", localAddress: "100.101.102.103",
                                     scServiceName: nil, runningBundleIDs: []), "Tailscale")
        XCTAssertNil(VPNNamer.name(interface: "utun0", localAddress: "10.8.0.2",
                                   scServiceName: nil, runningBundleIDs: []))
    }
    func testKnownBundleIDs() {
        XCTAssertEqual(VPNNamer.name(interface: "utun4", localAddress: "10.8.0.2",
                                     scServiceName: nil,
                                     runningBundleIDs: ["com.apple.dock", "net.openvpn.connect.app"]), "OpenVPN")
    }
    func testCorrectedPureVPNBundleID() {
        XCTAssertEqual(VPNNamer.name(interface: "utun4", localAddress: nil,
                                     scServiceName: nil, runningBundleIDs: ["com.purevpn.app.mac"]), "PureVPN")
    }
    func testNonTunnelInterfaceGetsNoName() {
        XCTAssertNil(VPNNamer.name(interface: "en0", localAddress: "192.168.1.5",
                                   scServiceName: "PureVPN", runningBundleIDs: ["net.openvpn.connect.app"]))
    }

    /// THE BUG: Tailscale.app is still running (but disconnected) while PureVPN owns the
    /// actual default-route tunnel. The route-correlated SC service name MUST win over the
    /// presence-based bundle-ID table, even though Tailscale's bundle id is running and is
    /// first in the table.
    func testSCServiceNameWinsOverRunningButDisconnectedApp() {
        XCTAssertEqual(VPNNamer.name(interface: "utun13", localAddress: "172.22.5.2",
                                     scServiceName: "PureVPN",
                                     runningBundleIDs: ["io.tailscale.ipn.macos", "com.purevpn.app.mac"]),
                      "PureVPN")
    }

    func testLastResortBundleTableStillWorksWhenOnlyCandidate() {
        XCTAssertEqual(VPNNamer.name(interface: "utun4", localAddress: "10.8.0.2",
                                     scServiceName: nil,
                                     runningBundleIDs: ["io.tailscale.ipn.macos"]), "Tailscale")
    }

    /// The CLI has no AppKit, so runningBundleIDs is always empty there — WARP can only be
    /// named via its fixed tunnel address, field-verified 2026-08-17 (172.16.0.2).
    func testWARPByTunnelAddress() {
        XCTAssertEqual(VPNNamer.name(interface: "utun16", localAddress: "172.16.0.2",
                                     scServiceName: nil, runningBundleIDs: []), "Cloudflare WARP")
    }

    func testOtherAddressInWARPSubnetDoesNotMatch() {
        XCTAssertNil(VPNNamer.name(interface: "utun16", localAddress: "172.16.0.3",
                                   scServiceName: nil, runningBundleIDs: []))
    }

    /// A2: native IKEv2 personal VPNs have no reachable name anywhere — a generic but
    /// truthful label beats nil.
    func testIPSecWithNoOtherTellsGetsGenericIKEv2Label() {
        XCTAssertEqual(VPNNamer.name(interface: "ipsec0", localAddress: nil,
                                     scServiceName: nil, runningBundleIDs: []), "IKEv2 VPN")
    }

    func testIPSecWithSCServiceNameStillWins() {
        XCTAssertEqual(VPNNamer.name(interface: "ipsec0", localAddress: nil,
                                     scServiceName: "Corp VPN", runningBundleIDs: []), "Corp VPN")
    }
}
