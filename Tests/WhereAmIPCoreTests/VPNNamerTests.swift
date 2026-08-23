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

    // MARK: - C1: classic daemon tunnel process evidence

    /// THE field bug: office ovpnagent daemon tunnel registers no SC State keys at all, and
    /// Tailscale.app happens to be running in the background too — the bundle table alone
    /// would pick "Tailscale" by table order. Process evidence must fire first.
    func testOpenVPNDaemonNamedByOvpnagentProcessEvenWithTailscaleAppRunning() {
        XCTAssertEqual(VPNNamer.name(interface: "utun17", localAddress: "192.168.4.4",
                                     scServiceName: nil, runningBundleIDs: ["io.tailscale.ipn.macos"],
                                     runningProcessNames: ["ovpnagent"]), "OpenVPN")
    }
    func testOpenVPNDaemonNamedByOpenvpnProcess() {
        XCTAssertEqual(VPNNamer.name(interface: "utun17", localAddress: "192.168.4.4",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["openvpn"]), "OpenVPN")
    }
    func testSCServiceNameWinsOverProcessEvidence() {
        XCTAssertEqual(VPNNamer.name(interface: "utun17", localAddress: "192.168.4.4",
                                     scServiceName: "PureVPN", runningBundleIDs: [],
                                     runningProcessNames: ["openvpn"]), "PureVPN")
    }
    /// THE field bug (2026-08-23, maintainer's work tunnel): utun18 is OpenVPN Connect
    /// — `inet 192.168.4.3 --> 192.168.4.1`, hijack pair present, route attribution
    /// correct — but the menu said "VPN: unknown". `ovpnagent` runs as ROOT and is
    /// therefore invisible to an unprivileged `proc_name` scan (282 of 1284 pids
    /// returned nothing, all root-owned), so the daemon-name tell could never fire, and
    /// the bundle table was correctly nil (OpenVPN Connect + Tailscale + WARP all
    /// running → ambiguous). The user-owned GUI process is what's actually visible.
    func testOpenVPNConnectNamedByItsVisibleUserSpaceProcess() {
        XCTAssertEqual(VPNNamer.name(interface: "utun18", localAddress: "192.168.4.3",
                                     scServiceName: nil,
                                     runningBundleIDs: ["net.openvpn.connect.app",
                                                        "io.tailscale.ipn.macos",
                                                        "com.cloudflare.1dot1dot1dot1.macos"],
                                     runningProcessNames: ["OpenVPN Connect"]), "OpenVPN")
    }

    /// `proc_name` returns a truncated short name — this is the exact string observed in
    /// the field, cut mid-word. Equality matching would miss it; the prefix must not.
    func testTruncatedHelperProcessNameStillNamesTheTunnel() {
        XCTAssertEqual(VPNNamer.name(interface: "utun18", localAddress: "192.168.4.3",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["OpenVPN Connect Helper (Rendere"]),
                       "OpenVPN")
    }

    /// The prefix is only safe because of its POSITION in the ladder: a tunnel positively
    /// identified as Tailscale or WARP must never be captured by a merely-running OpenVPN
    /// Connect — which is exactly the situation on the affected machine, where all three
    /// apps run at once.
    func testCGNATTunnelStaysTailscaleEvenWithOpenVPNConnectRunning() {
        XCTAssertEqual(VPNNamer.name(interface: "utun5", localAddress: "100.101.102.103",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["OpenVPN Connect", "OpenVPN Connect Helper"]),
                       "Tailscale")
    }
    func testWARPTunnelStaysWARPEvenWithOpenVPNConnectRunning() {
        XCTAssertEqual(VPNNamer.name(interface: "utun16", localAddress: "172.16.0.2",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["OpenVPN Connect"]), "Cloudflare WARP")
    }

    /// The prefix must not turn into "anything vaguely VPN-ish": an unrelated process set
    /// still yields no name at all.
    func testUnrelatedProcessesNamedNothing() {
        XCTAssertNil(VPNNamer.name(interface: "utun18", localAddress: "192.168.4.3",
                                   scServiceName: nil, runningBundleIDs: [],
                                   runningProcessNames: ["Finder", "Slack Helper", "vpnkit", "ovpn"]))
    }

    func testNoMatchingProcessesFallsThroughPastProcessTell() {
        XCTAssertNil(VPNNamer.name(interface: "utun17", localAddress: "192.168.4.4",
                                   scServiceName: nil, runningBundleIDs: [],
                                   runningProcessNames: ["Finder", "WindowServer"]))
    }

    // MARK: - C2: ambiguity-aware bundle table

    func testAmbiguousMultipleVendorAppsRunningReturnsNil() {
        XCTAssertNil(VPNNamer.name(interface: "utun4", localAddress: "10.8.0.2",
                                   scServiceName: nil,
                                   runningBundleIDs: ["io.tailscale.ipn.macos", "net.openvpn.connect.app"]))
    }
    func testSameVendorMultipleBundleIDsStillNamed() {
        XCTAssertEqual(VPNNamer.name(interface: "utun4", localAddress: "10.8.0.2",
                                     scServiceName: nil,
                                     runningBundleIDs: ["io.tailscale.ipn.macos", "io.tailscale.ipn.macsys"]),
                      "Tailscale")
    }
}
