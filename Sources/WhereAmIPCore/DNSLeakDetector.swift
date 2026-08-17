import Foundation

/// Pure DNS leak verdict — a transition table, not a counter. The two-consecutive-refresh
/// confirmation gate lives in the .suspected → .confirmed edge; Monitor holds NO extra
/// leak-tracking state (the 20def2d lesson: hidden mutable coordination breeds false alarms).
public enum DNSLeakDetector {
    public static func decide(egress: (ip: String, isIPv6: Bool)?,
                              exit4: ExitInfo?,   // caller passes nil unless fresh THIS refresh
                              exit6: ExitInfo?,   // fresh-or-nil by construction
                              route: RouteInfo,
                              previous: DNSLeak,
                              egressASN: Int? = nil, egressOrg: String? = nil,
                              egressProvider: String? = nil,
                              intentionalDelegation: Bool = false) -> DNSLeak {
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
        // Org/ASN rescue (external review, field-verified by 3 providers): a resolver that
        // egresses from the SAME OPERATOR as the tunnel exit is the provider's own DNS, not
        // a leak. Conservative by construction: ASN equality first; exact normalized org
        // equality only within the same geo provider; any missing datum -> no rescue.
        if !egress.isIPv6, route.isVPN, let e4 = exit4,
           sameOperator(egressASN: egressASN, egressOrg: egressOrg, egressProvider: egressProvider, exit: e4) {
            return .none
        }
        if egress.isIPv6, route.v6IsVPN, let e6 = exit6,
           sameOperator(egressASN: egressASN, egressOrg: egressOrg, egressProvider: egressProvider, exit: e6) {
            return .none
        }
        // 3: the egress's stack is tunneled but we have no fresh exit to compare — can't judge.
        if !egress.isIPv6, route.isVPN, exit4 == nil { return previous == .confirmed ? .confirmed : .unknown }
        if egress.isIPv6, route.v6IsVPN, exit6 == nil { return previous == .confirmed ? .confirmed : .unknown }
        // 4: mismatch — including DNS escaping over the NON-tunneled stack (cross-stack leak).
        //
        // Escalating .suspected/.confirmed onward to .confirmed is the real false-notification
        // vector (adjudicated fix, external review round 2). The gate below applies ONLY to a
        // SAME-STACK mismatch — egress's own stack IS the tunneled one, its judged exit (e4/e6)
        // is present, and it already failed both the IP match and the org/ASN rescue above. In
        // that case, hold at .suspected (never advance) ONLY when a rescue was genuinely
        // possible but unevaluable: the judged exit itself carries real attribution (a non-zero
        // ASN or a non-empty org) yet the egress lookup came back with neither — i.e. we simply
        // couldn't compare, not that we compared and found a mismatch. If the judged exit has NO
        // attribution at all, there was never anything to rescue against, so plain escalation
        // proceeds exactly as pre-Wave-B.
        //
        // A CROSS-STACK mismatch (egress's own stack was never tunneled — routing alone already
        // proves the leak) never reaches the rescue path above at all, so attribution is
        // irrelevant there: `judgedExit` is nil and escalation proceeds unconditionally, exactly
        // as pre-Wave-B.
        let judgedExit: ExitInfo? = !egress.isIPv6 ? (route.isVPN ? exit4 : nil)
                                                    : (route.v6IsVPN ? exit6 : nil)
        if let judgedExit, previous == .suspected || previous == .confirmed {
            let exitHasAttribution = meaningfulASN(judgedExit.asn) != nil || meaningfulOrg(judgedExit.org) != nil
            let egressAttributionMissing = meaningfulASN(egressASN) == nil && meaningfulOrg(egressOrg) == nil
            if exitHasAttribution, egressAttributionMissing { return previous }
        }
        // Tailscale's MagicDNS (documented resolver 100.100.100.100) intentionally delegates DNS
        // to a user-configured upstream — a genuine third-party egress that is the product working
        // as designed, indistinguishable from a leak by operator comparison alone. Policy (user
        // decision 2026-08-17): visible as "suspected" in dropdown/CLI, never confirms, never
        // notifies. https://tailscale.com/kb/1081/magicdns
        if intentionalDelegation, previous == .suspected { return .suspected }
        return (previous == .suspected || previous == .confirmed) ? .confirmed : .suspected
    }

    /// True iff `exit` egresses from the same network operator as the DNS resolver's egress,
    /// established conservatively: ASN equality first (cheapest, least ambiguous), or — only
    /// when both org strings came from the SAME geo provider (cross-provider org strings for
    /// the same operator can differ cosmetically) — an EXACT normalized org match. Containment
    /// ("PureVPN" vs "PureVPN S.A.") deliberately does NOT count: this rule can only SUPPRESS a
    /// leak warning, so every comparison stays maximally conservative. Any missing OR
    /// non-meaningful datum (nil/zero ASN, nil/empty org, provider mismatch, failed lookup)
    /// means no rescue — behavior is unchanged from today.
    static func sameOperator(egressASN: Int?, egressOrg: String?, egressProvider: String?,
                             exit: ExitInfo) -> Bool {
        if let a = meaningfulASN(egressASN), let b = meaningfulASN(exit.asn), a == b { return true }
        guard let egressProvider, egressProvider == exit.provider,
              let egressOrg = meaningfulOrg(egressOrg), let exitOrg = meaningfulOrg(exit.org)
        else { return false }
        return egressOrg == exitOrg
    }

    /// `nil` unless `asn` is present AND non-zero. Live-verified regression (external review
    /// round 2): ipwho.is returns `asn: 0` for IPs it can't attribute — including the exact ECS
    /// network-address shape Monitor feeds it (e.g. "1.2.3.0" from an ECS answer "1.2.3.0/24").
    /// Treating 0 as a real ASN would let two UNATTRIBUTED sides "match" each other (0 == 0) and
    /// rescue a genuine mismatch — even clearing an already-.confirmed alarm. 0 is a sentinel for
    /// "unknown", not a real autonomous system number; must never participate in equality.
    static func meaningfulASN(_ asn: Int?) -> Int? {
        guard let asn, asn != 0 else { return nil }
        return asn
    }

    /// `nil` unless `org`, once normalized, is non-empty. An empty string trivially satisfies
    /// Swift's `String == String` (`"" == ""`), which would otherwise let two ORGLESS sides
    /// "rescue" each other — same failure class as the ASN-0 sentinel above.
    static func meaningfulOrg(_ org: String?) -> String? {
        guard let org else { return nil }
        let normalized = normalizeOrg(org)
        return normalized.isEmpty ? nil : normalized
    }

    /// Lowercased, trimmed, with internal whitespace runs collapsed to a single space — used
    /// only for the org-equality fallback in `sameOperator`/`meaningfulOrg`. Deliberately NOT a
    /// fuzzy match: still requires exact equality after normalization, never containment/substring.
    static func normalizeOrg(_ s: String) -> String {
        s.lowercased()
         .split(whereSeparator: { $0.isWhitespace })
         .joined(separator: " ")
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
