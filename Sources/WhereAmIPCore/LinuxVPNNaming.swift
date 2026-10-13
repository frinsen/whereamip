#if os(Linux)
import Foundation

/// Tunnel detection on Linux, structural first. macOS tunnels are recognisable by name
/// alone (`utun`, `ppp`, `ipsec`); Linux interface names are free-form — wg-quick takes
/// the config file's name, NetworkManager its own, a user can call a WireGuard link
/// `office` — so the kernel's own facts decide, and names are only the fast path.
enum LinuxTunnel {
    /// Name prefixes that are tunnels by construction on Linux (kernel/driver defaults and
    /// the defaults of the common clients). Kept short on purpose: anything missing here is
    /// still caught by `isTunnelLink`.
    static let namePrefixes = ["tun", "tap", "wg", "tailscale", "nordlynx", "nordtun"]

    /// IMPURE: what sysfs says about the link. A tun/tap device carries `tun_flags`; a
    /// WireGuard link reports DEVTYPE=wireguard; PPP and the IP-in-IP family have their own
    /// ARPHRD types; and a TUN device without that file still has ARPHRD_NONE.
    static func isTunnelLink(_ name: String) -> Bool {
        let base = "/sys/class/net/\(name)"
        guard !name.isEmpty, !name.contains("/"), LinuxSystem.exists(base) else { return false }
        if LinuxSystem.exists("\(base)/tun_flags") { return true }
        let devType = InterfaceKind.ueventValue("DEVTYPE", in: LinuxSystem.read("\(base)/uevent") ?? "")
        let arphrd = LinuxSystem.read("\(base)/type").flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return isTunnel(devType: devType, arphrdType: arphrd)
    }

    /// PURE, tested.
    static func isTunnel(devType: String?, arphrdType: Int?) -> Bool {
        if devType == "wireguard" { return true }
        switch arphrdType {
        case 65534,            // ARPHRD_NONE: TUN, WireGuard
             512,              // ARPHRD_PPP
             768, 769,         // ARPHRD_TUNNEL, ARPHRD_TUNNEL6 (ipip, ip6tnl, vti)
             776,              // ARPHRD_SIT
             778, 823:         // ARPHRD_IPGRE, ARPHRD_IP6GRE
            return true
        default:
            return false
        }
    }
}

/// The Linux counterpart of `SCServiceNamer`: the name of the connection that owns a
/// tunnel interface — what feeds `VPNNamer.name`'s `scServiceName` slot, the structural,
/// route-correlated, vendor-neutral answer that wins over every fingerprint.
///
/// Two sources, in this order:
///   1. NetworkManager. Any VPN set up in the network settings (WireGuard, OpenVPN,
///      IPsec, a vendor's NM plugin) is a connection with a user-visible name, and NM knows
///      which interface it runs on. That is the macOS service-name path, almost verbatim.
///   2. Interface names a vendor's own client assigns: the same evidence class as WARP's
///      fixed 172.16.0.2 on macOS — a value the vendor chose — so it identifies the vendor
///      on its own. Only for clients that bypass NetworkManager.
enum LinuxServiceNamer {
    static func serviceName(forInterface interface: String) -> String? {
        networkManagerName(forInterface: interface) ?? vendorInterfaceName(interface)
    }

    // MARK: - NetworkManager

    static func networkManagerName(forInterface interface: String) -> String? {
        // The device's own connection: right for WireGuard and anything else NM drives
        // directly on the tunnel interface.
        if let output = LinuxSystem.run("nmcli", ["-t", "-f", "GENERAL.CONNECTION", "device", "show", interface]),
           let name = connectionName(deviceShow: output, interface: interface) {
            return name
        }
        // Plugin VPNs (OpenVPN, OpenConnect, strongSwan via NM) are active connections whose
        // DEVICE is the underlying link, not the tunnel; their IP interface is the tunnel.
        // Only an exact IP-IFACE match names one — two active VPNs and a manual tunnel must
        // never be resolved by guessing which is which.
        guard let active = LinuxSystem.run("nmcli", ["-t", "-f", "NAME,UUID,TYPE", "connection", "show", "--active"])
        else { return nil }
        for connection in activeConnections(terse: active) where connection.type == "vpn" {
            guard let ipIface = LinuxSystem.run("nmcli", ["-g", "GENERAL.IP-IFACE", "connection", "show",
                                                          "--active", "uuid", connection.uuid]) else { continue }
            if unescapeTerse(ipIface.trimmingCharacters(in: .whitespacesAndNewlines)) == interface {
                return connection.name
            }
        }
        return nil
    }

    /// PURE, tested. `GENERAL.CONNECTION:<name>` from `nmcli -t device show`. NM names a
    /// connection it merely observed (one it did not create — wg-quick, tailscaled, a manual
    /// openvpn) after the interface itself, which is no name at all; that, `--` and empty
    /// all mean "NetworkManager has nothing to say".
    static func connectionName(deviceShow output: String, interface: String) -> String? {
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("GENERAL.CONNECTION:") else { continue }
            let value = unescapeTerse(String(line.dropFirst("GENERAL.CONNECTION:".count)))
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value != "--", value != interface else { return nil }
            return value
        }
        return nil
    }

    struct ActiveConnection: Equatable {
        let name: String
        let uuid: String
        let type: String
    }

    /// PURE, tested. `nmcli -t` separates fields with `:` and escapes a literal `:` or `\`
    /// inside a value with a backslash — connection names are user-chosen and may contain
    /// either.
    static func activeConnections(terse output: String) -> [ActiveConnection] {
        output.split(separator: "\n").compactMap { line in
            let fields = splitTerse(String(line))
            guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            return ActiveConnection(name: fields[0], uuid: fields[1], type: fields[2])
        }
    }

    static func splitTerse(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var escaped = false
        for ch in line {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == ":" {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    static func unescapeTerse(_ value: String) -> String {
        splitTerse(value).joined(separator: ":")
    }

    // MARK: - vendor-assigned interface names

    /// Interface names the vendor's own Linux client creates by default. Each entry is a
    /// constant that vendor chose, so a match identifies it without further corroboration
    /// — the same bar the WARP 172.16.0.2 tell meets on macOS. Ambiguous defaults (`tun0`,
    /// `wg0`) are exactly what is NOT in here.
    static let vendorInterfaces: [(matches: (String) -> Bool, name: String)] = [
        ({ $0.hasPrefix("tailscale") }, "Tailscale"),            // tailscaled --tun=tailscale0
        ({ $0 == "CloudflareWARP" }, "Cloudflare WARP"),         // warp-svc
        ({ $0 == "nordlynx" || $0 == "nordtun" }, "NordVPN"),    // NordLynx / OpenVPN mode
        ({ $0.lowercased().contains("mullvad") }, "Mullvad"),    // wg0-mullvad / wg-mullvad
    ]

    /// PURE, tested.
    static func vendorInterfaceName(_ interface: String) -> String? {
        vendorInterfaces.first { $0.matches(interface) }?.name
    }
}
#endif
