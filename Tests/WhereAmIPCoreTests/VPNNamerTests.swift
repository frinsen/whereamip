import XCTest
@testable import WhereAmIPCore

final class VPNNamerTests: XCTestCase {
    /// 100.64/10 is RFC 6598 carrier-grade NAT — a PUBLIC range Tailscale merely uses, so
    /// the address is a Tailscale tell only when Tailscale's own evidence corroborates it.
    func testCGNATNamesTailscaleWhenCorroboratedByItsBundleID() {
        XCTAssertEqual(VPNNamer.name(interface: "utun0", localAddress: "100.101.102.103",
                                     scServiceName: nil,
                                     runningBundleIDs: ["io.tailscale.ipn.macos"]), "Tailscale")
    }

    /// The CLI has no AppKit and passes no bundle ids, so the process side has to carry it.
    /// Both names verified present on a real machine running Tailscale: the unprivileged
    /// scanner sees the user-owned GUI app and its network extension. Root `tailscaled` it
    /// does NOT see, which is why nothing here looks for that.
    func testCGNATNamesTailscaleWhenCorroboratedByItsVisibleProcesses() {
        for process in ["Tailscale", "IPNExtension"] {
            XCTAssertEqual(VPNNamer.name(interface: "utun0", localAddress: "100.101.102.103",
                                         scServiceName: nil, runningBundleIDs: [],
                                         runningProcessNames: [process]), "Tailscale", process)
        }
    }

    /// THE generalisation bug: another mesh VPN (Headscale, NetBird, Nebula) or a plain
    /// CGNAT'd uplink lives in exactly this range. Uncorroborated, it must NOT be named
    /// Tailscale.
    func testUncorroboratedCGNATIsNotNamedTailscale() {
        XCTAssertNil(VPNNamer.name(interface: "utun0", localAddress: "100.101.102.103",
                                   scServiceName: nil, runningBundleIDs: [],
                                   runningProcessNames: ["Finder", "NetBird"]))
    }

    /// Falling THROUGH, not falling over: the rest of the ladder still gets its turn, so an
    /// unambiguous bundle table can still name a CGNAT tunnel.
    func testUncorroboratedCGNATStillFallsThroughToTheBundleTable() {
        XCTAssertEqual(VPNNamer.name(interface: "utun0", localAddress: "100.101.102.103",
                                     scServiceName: nil,
                                     runningBundleIDs: ["com.wireguard.macos"]), "WireGuard")
    }

    func testCGNATRangeBoundariesStillRecognisedWhenCorroborated() {
        for address in ["100.64.0.1", "100.127.255.254"] {
            XCTAssertEqual(VPNNamer.name(interface: "utun0", localAddress: address,
                                         scServiceName: nil, runningBundleIDs: [],
                                         runningProcessNames: ["Tailscale"]), "Tailscale", address)
        }
        XCTAssertNil(VPNNamer.name(interface: "utun0", localAddress: "10.8.0.2",
                                   scServiceName: nil, runningBundleIDs: [],
                                   runningProcessNames: ["Tailscale"]))
    }

    /// WARP's 172.16.0.2 is a constant the vendor's own client assigns — a vendor-chosen
    /// value, not a public range — so it stays uncorroborated by design.
    func testWARPFixedAddressNeedsNoCorroboration() {
        XCTAssertEqual(VPNNamer.name(interface: "utun16", localAddress: "172.16.0.2",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["Finder"]), "Cloudflare WARP")
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
        // The real situation on the affected machine: Tailscale AND OpenVPN Connect both
        // running. Tailscale is corroborated, so its tell fires first and the looser
        // OpenVPN process match never gets to capture the tunnel.
        XCTAssertEqual(VPNNamer.name(interface: "utun5", localAddress: "100.101.102.103",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["Tailscale", "OpenVPN Connect",
                                                           "OpenVPN Connect Helper"]),
                       "Tailscale")
    }

    /// The deliberate consequence of requiring corroboration, recorded so it can't be
    /// mistaken for a regression: a CGNAT address with NO Tailscale evidence is not
    /// Tailscale's to claim, so the ladder continues and the running OpenVPN client — real,
    /// visible evidence — names it. Failing downward to the next piece of evidence is the
    /// intended behaviour; failing sideways into "Tailscale" on a shared public range is not.
    func testUncorroboratedCGNATFallsThroughToTheOpenVPNProcessTell() {
        XCTAssertEqual(VPNNamer.name(interface: "utun5", localAddress: "100.101.102.103",
                                     scServiceName: nil, runningBundleIDs: [],
                                     runningProcessNames: ["OpenVPN Connect"]), "OpenVPN")
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
    // MARK: - diagnosis: why an unnamed tunnel stayed unnamed

    func testNamedTunnelHasNoDiagnosis() {
        XCTAssertNil(VPNNamer.diagnosis(interface: "utun18", localAddress: "192.168.4.3",
                                        scServiceName: nil, runningBundleIDs: [],
                                        runningProcessNames: ["OpenVPN Connect"]))
        XCTAssertNil(VPNNamer.diagnosis(interface: "utun4", localAddress: nil,
                                        scServiceName: "Corp VPN", runningBundleIDs: []))
    }

    func testNonTunnelInterfaceHasNoDiagnosis() {
        XCTAssertNil(VPNNamer.diagnosis(interface: "en0", localAddress: "192.168.1.5",
                                        scServiceName: nil, runningBundleIDs: []))
    }

    /// The fact a stranger's bug report needs to carry: the bundle table didn't decline
    /// because it knows nothing, it declined because it knew two things at once.
    func testUnnamedTunnelRecordsTheAmbiguityThatBlockedTheBundleTable() {
        let diagnosis = VPNNamer.diagnosis(
            interface: "utun4", localAddress: "10.8.0.2", scServiceName: nil,
            runningBundleIDs: ["io.tailscale.ipn.macos", "com.purevpn.app.mac", "com.apple.dock"])
        XCTAssertEqual(diagnosis?.hasServiceName, false)
        XCTAssertEqual(diagnosis?.knownVPNApps, ["PureVPN", "Tailscale"])   // sorted, deduped
    }

    func testUnnamedTunnelWithNoKnownAppsRecordsThatToo() {
        let diagnosis = VPNNamer.diagnosis(interface: "utun4", localAddress: "10.8.0.2",
                                           scServiceName: nil, runningBundleIDs: ["com.apple.dock"])
        XCTAssertEqual(diagnosis?.knownVPNApps, [])
    }

    func testSameVendorMultipleBundleIDsStillNamed() {
        XCTAssertEqual(VPNNamer.name(interface: "utun4", localAddress: "10.8.0.2",
                                     scServiceName: nil,
                                     runningBundleIDs: ["io.tailscale.ipn.macos", "io.tailscale.ipn.macsys"]),
                      "Tailscale")
    }
}
