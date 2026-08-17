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
    /// route-correlated answer from SCDynamicStore; (c) CGNAT 100.64/10 source address →
    /// "Tailscale"; (d) classic daemon-tunnel process evidence (see below); (e) bundle-ID
    /// presence table, as a last resort only (a running-but-disconnected VPN app must never
    /// win over the route-owning service's real name).
    public static func name(interface: String, localAddress: String?,
                            scServiceName: String?, runningBundleIDs: [String],
                            runningProcessNames: Set<String> = []) -> String? {
        guard RouteInspector.isTunnelInterface(interface) else { return nil }
        if let scServiceName { return scServiceName }
        // Tailscale tell: CGNAT 100.64.0.0/10 source address
        if let addr = localAddress, isCGNAT(addr) { return "Tailscale" }
        // Cloudflare WARP tell: the client assigns 172.16.0.2 as its tunnel address
        // (fixed across installs; field-verified 2026-08-17). Bundle-ID lookup can't
        // help the CLI, which has no AppKit and passes empty runningBundleIDs.
        if localAddress == "172.16.0.2" { return "Cloudflare WARP" }
        // Classic daemon tunnels (OpenVPN etc.) register NOTHING in SCDynamicStore — after the
        // State-key widening, a nameless tunnel plus a running openvpn/ovpnagent process is
        // causal evidence (sibling-session field diagnosis 2026-08-17: office ovpnagent tunnel
        // misnamed "Tailscale" by bundle-table order).
        if runningProcessNames.contains(where: { $0 == "openvpn" || $0 == "ovpnagent" }) { return "OpenVPN" }
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
    static func isCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}
