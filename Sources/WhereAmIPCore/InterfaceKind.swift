import SystemConfiguration

/// Physical-interface classification via SCNetworkInterface — the system's own
/// interface type and localized display name ("Wi-Fi", "iPhone USB", …); no
/// hardcoded vendor knowledge (design rule: names come from the system).
public enum InterfaceKind {
    /// IMPURE: bsdName -> (kind, displayName) via SCNetworkInterfaceCopyAll.
    public static func lookup(bsdName: String) -> (kind: String, displayName: String)? {
        guard let ifaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for i in ifaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(i) as String?, bsd == bsdName else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(i) as String? ?? ""
            let display = SCNetworkInterfaceGetLocalizedDisplayName(i) as String?
            return (Self.kindLabel(type: type, display: display), display ?? bsdName)
        }
        return nil
    }
    /// PURE, tested: SC type string -> short kind label.
    static func kindLabel(type: String, display: String?) -> String {
        switch type {
        case "IEEE80211": return "Wi-Fi"
        case "Ethernet":
            // The system's display name distinguishes tethering/adapters ("iPhone USB",
            // "USB 10/100/1000 LAN") — pass it through rather than second-guessing.
            return display?.contains("iPhone") == true ? "iPhone USB" : "Ethernet"
        case "Bridge": return "Bridge"
        default: return type.isEmpty ? "Unknown" : type
        }
    }
}
