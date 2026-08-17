import Foundation

/// Attributes the "my router forwards to somebody" setup, the common home case: macOS is
/// configured with nothing but router-local resolvers, yet the queries come out at a well-known
/// public provider — so the router, not this Mac, decides that upstream hop.
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
    /// configured resolver must be router-local (otherwise this Mac talks to a public resolver
    /// directly and there is no forwarding hop to attribute) and at least one discovered egress
    /// resolver must be attributable to a known provider. Empty inputs mean "nothing measured",
    /// never a vacuous yes.
    ///
    /// `localPrefixes` defaults to a live getifaddrs snapshot; pass an explicit list (`[]` for
    /// none) to keep a caller deterministic.
    public static func provider(configured: [DNSResolver], egress: [EgressResolver],
                                localPrefixes: [InterfacePrefix] = RouteInspector.localPrefixes()) -> String? {
        guard !configured.isEmpty, !egress.isEmpty else { return nil }
        guard allRouterLocal(configured, localPrefixes: localPrefixes) else { return nil }
        return egress.lazy.compactMap { knownProvider($0.operatorName) }.first
    }

    /// PURE. Every configured resolver is this network's own gateway, one way or another.
    ///
    /// Two-pass because of a field case on a Fritz!Box: macOS keeps listing the router under a
    /// PREVIOUSLY delegated global prefix (ISPs rotate them) that this host no longer holds an
    /// address in, alongside the current one and a ULA. Those entries are the same physical box
    /// — identical IPv6 interface identifier — so the second pass accepts an address whose
    /// low 64 bits match one of the resolvers the first pass already anchored to this machine.
    /// Anchors only ever come from pass one: a set of addresses sharing an identifier can never
    /// bootstrap itself into being local, and a genuinely foreign resolver (2620:fe::fe) fails
    /// both passes. Only identifiers that actually identify a box participate — see
    /// `distinguishingIdentifier`.
    static func allRouterLocal(_ configured: [DNSResolver], localPrefixes: [InterfacePrefix]) -> Bool {
        let anchored = configured.filter { isRouterLocal($0.address, localPrefixes: localPrefixes) }
        guard !anchored.isEmpty else { return false }
        let routerIdentifiers = Set(anchored.compactMap { distinguishingIdentifier($0.address) })
        return configured.allSatisfy { resolver in
            isRouterLocal(resolver.address, localPrefixes: localPrefixes)
                || distinguishingIdentifier(resolver.address).map(routerIdentifiers.contains) == true
        }
    }

    /// PURE. On this machine's own network segment: either a private-range address, or inside
    /// one of the host's directly connected prefixes. The latter is what catches a router that
    /// advertises itself with a GLOBAL address out of the ISP's delegated prefix — it lives in
    /// the Mac's own /64, so no vendor or ISP knowledge is needed to recognize it.
    static func isRouterLocal(_ address: String, localPrefixes: [InterfacePrefix]) -> Bool {
        if isPrivate(address) { return true }
        // A /0 would match everything — never let a malformed snapshot turn this into a yes.
        return localPrefixes.contains { prefix in
            prefix.prefixLength > 0
                && DNSLeakDetector.ipMatches(address, prefixOrIP: "\(prefix.address)/\(prefix.prefixLength)")
        }
    }

    /// PURE. The interface identifier, but only when it plausibly identifies a specific box —
    /// nil otherwise, which makes the same-box rule decline rather than guess.
    ///
    /// The gate is entropy in the identifier's UPPER four bytes. Auto-configured identifiers
    /// always have it: EUI-64 carries the `ff:fe` marker in the middle, so its upper bytes are
    /// never all zero, and a random privacy identifier misses by 2^-32. HAND-NUMBERED networks
    /// (pfSense/MikroTik/ISP infrastructure convention) do not: gateways and public resolvers
    /// alike end in `::1`, so `::1` says "somebody numbered this by hand", not "this box".
    /// Without the gate, a router at fd00::1 would lend its identifier to a public resolver at
    /// 2a02:abcd:1234::1 that this Mac queries DIRECTLY — inventing a forwarding hop that isn't
    /// there. Applied to anchors as well as candidates (one function, so it cannot go on
    /// asymmetrically): a low-entropy anchor stays router-local, it just vouches for nobody.
    static func distinguishingIdentifier(_ address: String) -> [UInt8]? {
        guard let identifier = interfaceIdentifier(address) else { return nil }
        return identifier[0..<4].contains { $0 != 0 } ? identifier : nil
    }

    /// PURE. The low 64 bits of an IPv6 address — the part that identifies the interface itself
    /// rather than the network it currently sits in. nil for anything that isn't IPv6.
    static func interfaceIdentifier(_ address: String) -> [UInt8]? {
        var a = in6_addr()
        guard address.contains(":"), inet_pton(AF_INET6, address, &a) == 1 else { return nil }
        return withUnsafeBytes(of: a) { Array($0[8..<16]) }
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
