import WhereAmIPCore

public enum NotificationText {
    static func flag(_ iso: String?) -> String { iso.flatMap { Flags.emoji(countryCode: $0) } ?? "❓" }
    public static func text(for event: Event) -> (title: String, body: String)? {
        switch event {
        case .countryChanged(let from, let to, let vpnName):
            return ("Exit changed: \(flag(from)) → \(flag(to))",
                    vpnName.map { "\($0) took over the default route" } ?? "Exit country changed")
        case .ipChanged(let country, let fromOrg, let toOrg):
            return ("New exit IP in \(flag(country))",
                    [fromOrg, toOrg].compactMap { $0 }.joined(separator: " → "))
        case .connectivityLost(let hijack):
            return ("Internet unreachable",
                    hijack ? "OpenVPN hijack routes present — tunnel likely dead"
                           : "Network is up, probes failing")
        case .connectivityRestored(let country, let city, let org):
            return ("Back online: \(flag(country)) \(city ?? "")",
                    org ?? "")
        case .leakSuspected(let org):
            return ("⚠️ Possible VPN leak",
                    "VPN route active but traffic still exits via \(org ?? "your ISP")")
        case .privateRelayToggled(let active):
            return ("Private Relay \(active ? "ON" : "OFF")",
                    active ? "Safari traffic exits via Apple's relay" : "Safari traffic follows the system route")
        case .vpnRouteChanged:
            return nil   // route changes alone are visible in the flag; don't notify
        case .ipv6Leak(_, let org):
            return ("⚠️ IPv6 leak detected",
                    "IPv6 traffic exits via \(org ?? "your ISP") — your VPN only tunnels IPv4")
        case .dnsLeakConfirmed(let egressIP, _):
            return ("⚠️ DNS leak detected",
                    "DNS queries are answered outside your VPN tunnel"
                    + (egressIP.map { " — resolver egress \($0)" } ?? ""))
        }
    }
}
