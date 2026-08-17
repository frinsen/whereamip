import Foundation

/// Attributes the "my router forwards to somebody" setup, the common home case: macOS is
/// configured with nothing but private-range resolvers (the router), yet the queries come out
/// at a well-known public provider — so the router, not this Mac, decides that upstream hop.
///
/// Deliberately an attribution hint and nothing more. Whether that hop is ENCRYPTED is set on
/// the router and is not observable from here (the client only ever sees its own plaintext
/// hop to the gateway), so this never claims encryption — and never warns either: forwarding
/// to Quad9/Cloudflare/… is a normal, often deliberate configuration.
public enum DNSForwarderHint {
    /// Substring needles, matched case-insensitively against the egress operator name. WoodyNet
    /// is Packet Clearing House, which operates Quad9's anycast nodes — the name that actually
    /// shows up in attribution data for Quad9 egress, so it maps to the product users know.
    static let providers: [(needle: String, name: String)] = [
        ("woodynet", "Quad9"),
        ("quad9", "Quad9"),
        ("cloudflare", "Cloudflare"),
        ("google", "Google Public DNS"),
        ("nextdns", "NextDNS"),
    ]

    /// The provider to name, or nil when the setup isn't a router-forwarding one: EVERY
    /// configured resolver must be private-range (otherwise this Mac talks to a public resolver
    /// directly and there is no forwarding hop to attribute) and at least one discovered egress
    /// resolver must be attributable to a known provider. Empty inputs mean "nothing measured",
    /// never a vacuous yes.
    public static func provider(configured: [DNSResolver], egress: [EgressResolver]) -> String? {
        guard !configured.isEmpty, !egress.isEmpty else { return nil }
        guard configured.allSatisfy({ isPrivate($0.address) }) else { return nil }
        return egress.lazy.compactMap { knownProvider($0.operatorName) }.first
    }

    /// PURE. RFC1918 (10/8, 172.16/12, 192.168/16) plus IPv6 link-local (fe80::/10) and ULA
    /// (fd00::/8). Compared on parsed bytes, never on text: "fe80:0:0:0:0:0:0:1" and "fe80::1"
    /// are the same address, and a prefix-string check would miss one of them.
    static func isPrivate(_ address: String) -> Bool {
        if let v4 = RelayRanges.ipv4ToUInt32(address) {
            return v4 & 0xFF00_0000 == 0x0A00_0000        // 10.0.0.0/8
                || v4 & 0xFFF0_0000 == 0xAC10_0000        // 172.16.0.0/12
                || v4 & 0xFFFF_0000 == 0xC0A8_0000        // 192.168.0.0/16
        }
        var a = in6_addr()
        guard address.contains(":"), inet_pton(AF_INET6, address, &a) == 1 else { return false }
        return withUnsafeBytes(of: a) { b in
            (b[0] == 0xFE && b[1] & 0xC0 == 0x80)         // fe80::/10
                || b[0] == 0xFD                           // fd00::/8
        }
    }

    /// PURE. The provider a given operator name belongs to, or nil when it's nobody we know.
    static func knownProvider(_ operatorName: String?) -> String? {
        guard let operatorName, !operatorName.isEmpty else { return nil }
        let haystack = operatorName.lowercased()
        return providers.first { haystack.contains($0.needle) }?.name
    }
}
