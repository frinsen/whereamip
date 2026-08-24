/// Why naming a tunnel came up empty — recorded at measurement time, because the
/// evidence (SC service name, running apps, running processes) exists only there and is
/// gone by the time anything displays the state.
///
/// This is the contribution channel: an unnamed tunnel is a VPN this app has no
/// fingerprint for, and the person seeing it is the only one who can supply one. Their
/// Copy Diagnostics paste carrying "no service name; 2 known VPN apps running (…)" is
/// exactly what turns "it says VPN (utun4)" into an actionable issue.
public struct VPNNameDiagnosis: Equatable, Codable, Sendable {
    /// Whether SCDynamicStore had a service name for the interface. False is the
    /// SC-invisible classic-daemon case; a tunnel with a name never reaches here.
    public var hasServiceName: Bool
    /// Display names from the bundle-ID table whose apps were running — the input to the
    /// ambiguity guard. Two or more means the table deliberately declined to guess.
    public var knownVPNApps: [String]
    public init(hasServiceName: Bool, knownVPNApps: [String]) {
        self.hasServiceName = hasServiceName
        self.knownVPNApps = knownVPNApps
    }
}

public enum VPNNamer {
    static let bundleIDNames: [(id: String, name: String)] = [
        ("io.tailscale.ipn.macos", "Tailscale"), ("io.tailscale.ipn.macsys", "Tailscale"),
        ("net.openvpn.connect.app", "OpenVPN"), ("org.openvpn.client.app", "OpenVPN"),
        ("com.purevpn.app.mac", "PureVPN"), ("com.purevpn.osx", "PureVPN"),
        ("com.wireguard.macos", "WireGuard"),
        ("net.mullvad.vpn", "Mullvad"),
        ("com.nordvpn.osx", "NordVPN"),
        ("ch.protonvpn.mac", "Proton VPN"),
        ("com.expressvpn.ExpressVPN", "ExpressVPN"),
        ("com.cloudflare.1dot1dot1dot1.macos", "Cloudflare WARP"),
    ]
    /// Precedence: (a) non-tunnel interface → nil; (b) `scServiceName` — the authoritative,
    /// route-correlated answer from SCDynamicStore; (c) CGNAT 100.64/10 source address
    /// CORROBORATED by Tailscale's own evidence → "Tailscale"; (d) WARP's vendor-assigned
    /// 172.16.0.2; (e) classic daemon-tunnel process evidence (see below); (f) bundle-ID
    /// presence table, as a last resort only (a running-but-disconnected VPN app must never
    /// win over the route-owning service's real name); (g) a generic label for native IKEv2.
    ///
    /// The rule the whole ladder encodes: STRUCTURAL evidence generalises (a registered
    /// network service names any vendor's VPN, including ones this app has never heard of),
    /// FINGERPRINTS do not. A fingerprint is a guess about one vendor, so it must either be
    /// vendor-specific by construction (a value that vendor's client chose) or be
    /// corroborated by that vendor's own presence — and when it doesn't fire, it must fail
    /// DOWNWARD to the next evidence or to the honest generic label, never sideways into
    /// another vendor's brand name.
    public static func name(interface: String, localAddress: String?,
                            scServiceName: String?, runningBundleIDs: [String],
                            runningProcessNames: Set<String> = []) -> String? {
        guard RouteInspector.isTunnelInterface(interface) else { return nil }
        if let scServiceName { return scServiceName }
        // Tailscale tell: a CGNAT 100.64.0.0/10 source address — but ONLY with Tailscale's
        // own evidence next to it.
        //
        // The two address fingerprints in this ladder are NOT the same kind of claim, and
        // that is why only one of them needs corroboration:
        //   - 100.64/10 is RFC 6598 carrier-grade NAT space: public infrastructure that
        //     Tailscale merely uses. Headscale, NetBird, Nebula and a plain CGNAT'd uplink
        //     live there just as legitimately, so the address alone identifies a RANGE, not
        //     a vendor. Naming Tailscale off it would confidently mislabel every other mesh
        //     VPN — the exact "works on the maintainer's machine" failure this guards.
        //   - 172.16.0.2 (below) is a constant the WARP client itself assigns, inside RFC
        //     1918 space it picked. That is a vendor-chosen value, so it identifies the
        //     vendor on its own and needs no second signal.
        // Uncorroborated CGNAT falls THROUGH to the rest of the ladder: an unambiguous
        // bundle table may still name it, and otherwise it stays honestly unnamed. Failing
        // downward into a generic truth is always better than sideways into a wrong brand.
        if let addr = localAddress, isCGNAT(addr),
           hasTailscaleEvidence(runningBundleIDs: runningBundleIDs, runningProcessNames: runningProcessNames) {
            return "Tailscale"
        }
        // Cloudflare WARP tell: the client assigns 172.16.0.2 as its tunnel address
        // (fixed across installs; field-verified 2026-08-17). Bundle-ID lookup can't
        // help the CLI, which has no AppKit and passes empty runningBundleIDs.
        if localAddress == "172.16.0.2" { return "Cloudflare WARP" }
        // Classic daemon tunnels (OpenVPN etc.) register NOTHING in SCDynamicStore — after the
        // State-key widening, a nameless tunnel plus a running OpenVPN process is causal
        // evidence (sibling-session field diagnosis 2026-08-17: office ovpnagent tunnel
        // misnamed "Tailscale" by bundle-table order).
        if runningProcessNames.contains(where: isOpenVPNProcess) { return "OpenVPN" }
        // Only name from app presence when it's unambiguous — multiple known VPN apps running
        // means table ORDER would decide, and a wrong name shown confidently is worse than none.
        let matchedNames = Set(bundleIDNames.filter { runningBundleIDs.contains($0.id) }.map(\.name))
        if matchedNames.count == 1 { return matchedNames.first }
        // Native NE personal VPNs (IKEv2/IPsec profiles installed via Settings or MDM) expose
        // no name in SCDynamicStore or any other reachable store — field-verified 2026-08-17,
        // no Setup:/UserDefinedName entry exists for their ipsecN interface either. A truthful
        // generic label beats showing nothing at all. Kept last so it can never shadow a real
        // name from any of the tells above. The CGNAT/WARP tells above stay in place until A1's
        // widened SCServiceNamer scan is field-verified against them (reviewer requirement) —
        // they don't retire here.
        if interface.hasPrefix("ipsec") { return "IKEv2 VPN" }
        return nil
    }
    /// The diagnosis for a tunnel this namer could NOT name — nil for anything it named,
    /// and for non-tunnel interfaces. Same inputs as `name`, so the two can never disagree
    /// about whether a name was found.
    public static func diagnosis(interface: String, localAddress: String?,
                                 scServiceName: String?, runningBundleIDs: [String],
                                 runningProcessNames: Set<String> = []) -> VPNNameDiagnosis? {
        guard RouteInspector.isTunnelInterface(interface),
              name(interface: interface, localAddress: localAddress, scServiceName: scServiceName,
                   runningBundleIDs: runningBundleIDs, runningProcessNames: runningProcessNames) == nil
        else { return nil }
        let apps = Set(bundleIDNames.filter { runningBundleIDs.contains($0.id) }.map(\.name))
        return VPNNameDiagnosis(hasServiceName: scServiceName != nil, knownVPNApps: apps.sorted())
    }

    /// Tailscale's own evidence, in either currency this namer has: its bundle ids (GUI
    /// path, empty for the CLI) or a process name.
    ///
    /// Process names verified empirically on a machine running it (the unprivileged scanner
    /// sees only user-owned processes — see ProcessScanner): "Tailscale" (the GUI app) and
    /// "IPNExtension" (its network extension) are both visible. `tailscaled` is not, being
    /// root-owned, so it is deliberately not listed — a check for it would be dead code.
    /// The extension is matched exactly and by name because it is the one that survives when
    /// the GUI app is quit but the tunnel stays up.
    static func hasTailscaleEvidence(runningBundleIDs: [String], runningProcessNames: Set<String>) -> Bool {
        let tailscaleIDs = bundleIDNames.filter { $0.name == "Tailscale" }.map(\.id)
        if runningBundleIDs.contains(where: tailscaleIDs.contains) { return true }
        return runningProcessNames.contains { name in
            name.lowercased().hasPrefix("tailscale") || name == "IPNExtension"
        }
    }

    /// OpenVPN's processes as an UNPRIVILEGED scanner can actually see them.
    ///
    /// The original tell here was `== "openvpn" || == "ovpnagent"`, and on a real machine it
    /// was dead code: `proc_name` fails for processes owned by another user (see
    /// ProcessScanner's doc), and `ovpnagent` runs as root out of the OpenVPN Connect
    /// framework — so it is never in the set. Field measurement on the affected Mac: of 1284
    /// pids, 282 returned no name, every one of them root-owned, `ovpnagent` among them. The
    /// tunnel therefore showed as "VPN: unknown (utun18)" even though the route attribution
    /// was correct, and the bundle table couldn't rescue it either — OpenVPN Connect,
    /// Tailscale and WARP were all running, so the ambiguity guard correctly returned nil.
    ///
    /// What IS visible is the user-owned GUI side: "OpenVPN Connect" and its helpers. A
    /// case-insensitive `openvpn` PREFIX covers all of those plus the bare daemon, and a
    /// prefix rather than equality is required because `proc_name` returns a truncated short
    /// name — the field sample "OpenVPN Connect Helper (Rendere" is cut mid-word. Never match
    /// a full executable name here.
    ///
    /// The looseness is safe only because of WHERE this sits in the ladder: the SC service
    /// name, the Tailscale CGNAT tell and the WARP 172.16.0.2 tell all run first, so a tunnel
    /// positively identified as one of those can never be captured by a merely-running
    /// OpenVPN Connect. Do not move this check earlier.
    static func isOpenVPNProcess(_ name: String) -> Bool {
        name.lowercased().hasPrefix("openvpn") || name == "ovpnagent"
    }

    static func isCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}
