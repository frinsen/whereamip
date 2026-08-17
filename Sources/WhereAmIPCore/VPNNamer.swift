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
    /// "Tailscale"; (d) bundle-ID presence table, as a last resort only (a running-but-
    /// disconnected VPN app must never win over the route-owning service's real name).
    public static func name(interface: String, localAddress: String?,
                            scServiceName: String?, runningBundleIDs: [String]) -> String? {
        guard RouteInspector.isTunnelInterface(interface) else { return nil }
        if let scServiceName { return scServiceName }
        // Tailscale tell: CGNAT 100.64.0.0/10 source address
        if let addr = localAddress, isCGNAT(addr) { return "Tailscale" }
        // Cloudflare WARP tell: the client assigns 172.16.0.2 as its tunnel address
        // (fixed across installs; field-verified 2026-08-17). Bundle-ID lookup can't
        // help the CLI, which has no AppKit and passes empty runningBundleIDs.
        if localAddress == "172.16.0.2" { return "Cloudflare WARP" }
        for (id, name) in bundleIDNames where runningBundleIDs.contains(id) { return name }
        return nil
    }
    static func isCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }
}
