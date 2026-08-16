import Foundation

/// Pure DNS leak verdict — a transition table, not a counter. The two-consecutive-refresh
/// confirmation gate lives in the .suspected → .confirmed edge; Monitor holds NO extra
/// leak-tracking state (the 20def2d lesson: hidden mutable coordination breeds false alarms).
public enum DNSLeakDetector {
    public static func decide(egress: (ip: String, isIPv6: Bool)?,
                              exit4: ExitInfo?,   // caller passes nil unless fresh THIS refresh
                              exit6: ExitInfo?,   // fresh-or-nil by construction
                              route: RouteInfo,
                              previous: DNSLeak) -> DNSLeak {
        // 0: no tunnel anywhere — nothing can leak, and a gone tunnel clears stale alarms.
        guard route.isVPN || route.v6IsVPN else { return .none }
        // 1: no measurement — never judge, never let failure CLEAR a confirmed alarm.
        guard let egress else { return previous == .confirmed ? .confirmed : .unknown }
        // 1b: a measurement that carries no information is a failed measurement, not
        // evidence in either direction. Zero-scope prefixes ("/0") match everything —
        // reporting .none from them would clear a real alarm; unparseable strings match
        // nothing — reporting .suspected from them would raise a false one. Both collapse
        // to rule 1's outcome.
        guard isMeaningful(egress.ip) else { return previous == .confirmed ? .confirmed : .unknown }
        // 2: matched a tunnel-stack exit → queries go through the tunnel.
        if !egress.isIPv6, route.isVPN, let e4 = exit4, ipMatches(e4.ip, prefixOrIP: egress.ip) { return .none }
        if egress.isIPv6, route.v6IsVPN, let e6 = exit6, ipMatches(e6.ip, prefixOrIP: egress.ip) { return .none }
        // 3: the egress's stack is tunneled but we have no fresh exit to compare — can't judge.
        if !egress.isIPv6, route.isVPN, exit4 == nil { return previous == .confirmed ? .confirmed : .unknown }
        if egress.isIPv6, route.v6IsVPN, exit6 == nil { return previous == .confirmed ? .confirmed : .unknown }
        // 4: mismatch — including DNS escaping over the NON-tunneled stack (cross-stack leak).
        return (previous == .suspected || previous == .confirmed) ? .confirmed : .suspected
    }

    /// True when s is a bare IPv4/IPv6 literal or a prefix "net/bits" with bits > 0 and a
    /// parseable network of the same family (bits capped at 32 for v4, 128 for v6).
    static func isMeaningful(_ s: String) -> Bool {
        guard let slash = s.firstIndex(of: "/") else {
            if RelayRanges.ipv4ToUInt32(s) != nil { return true }
            var a = in6_addr()
            return s.contains(":") && inet_pton(AF_INET6, s, &a) == 1
        }
        guard let bits = Int(s[s.index(after: slash)...]), bits > 0 else { return false }
        let network = String(s[..<slash])
        if network.contains(":") {
            var a = in6_addr()
            return bits <= 128 && inet_pton(AF_INET6, network, &a) == 1
        }
        return bits <= 32 && RelayRanges.ipv4ToUInt32(network) != nil
    }

    /// Exact match (v6 compared canonically via inet_pton) or ECS-prefix match ("1.2.3.0/24").
    static func ipMatches(_ ip: String, prefixOrIP: String) -> Bool {
        guard let slash = prefixOrIP.firstIndex(of: "/") else {
            if ip == prefixOrIP { return true }
            // v6 textual forms differ ("::5" vs ":0:5") — compare parsed bytes.
            if ip.contains(":"), prefixOrIP.contains(":") {
                var a = in6_addr(), b = in6_addr()
                return inet_pton(AF_INET6, ip, &a) == 1 && inet_pton(AF_INET6, prefixOrIP, &b) == 1
                    && withUnsafeBytes(of: a) { ab in withUnsafeBytes(of: b) { ab.elementsEqual($0) } }
            }
            return false
        }
        guard let bits = Int(prefixOrIP[prefixOrIP.index(after: slash)...]) else { return false }
        let network = String(prefixOrIP[..<slash])
        if !network.contains(":") {
            guard (0...32).contains(bits),
                  let n = RelayRanges.ipv4ToUInt32(network), let v = RelayRanges.ipv4ToUInt32(ip)
            else { return false }
            let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << (32 - bits)
            return (v & mask) == (n & mask)
        }
        guard (0...128).contains(bits) else { return false }
        var n = in6_addr(), v = in6_addr()
        guard inet_pton(AF_INET6, network, &n) == 1, inet_pton(AF_INET6, ip, &v) == 1 else { return false }
        return withUnsafeBytes(of: n) { nb in withUnsafeBytes(of: v) { vb in
            var remaining = bits
            for i in 0..<16 {
                let take = min(8, remaining); remaining -= take
                if take == 0 { return true }
                let mask: UInt8 = take == 8 ? 0xFF : ~(0xFF >> take)
                if (nb[i] & mask) != (vb[i] & mask) { return false }
            }
            return true
        } }
    }
}
