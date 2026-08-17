import Foundation

/// One resolver observed answering our lookups at the egress — the far end of the recursive
/// chain, i.e. the address a queried authoritative server actually saw. Everything past `ip`
/// is best-effort: dnscheck.tools reports operator/location from its own attribution data and
/// the transport from the connection it received, any of which can be absent.
public struct EgressResolver: Equatable, Codable, Sendable {
    public var ip: String
    public var port: Int?
    public var operatorName: String?
    public var location: String?     // raw "City, Region, CC" as reported — see `displayLine`
    public var transport: String?    // "UDP" / "TCP" / "TLS"
    public init(ip: String, port: Int? = nil, operatorName: String? = nil,
                location: String? = nil, transport: String? = nil) {
        self.ip = ip; self.port = port
        self.operatorName = operatorName; self.location = location; self.transport = transport
    }
}

public extension EgressResolver {
    /// "185.44.108.99 — WoodyNet, Inc. (Berlin, DE) · UDP", dropping whatever is missing. One
    /// source of truth for the dropdown submenu and any other frontend (same precedent as
    /// `ExitInfo.splitLine`). The middle "State of Berlin" component is dropped: a menu row has
    /// no width for an administrative region, and city + country code already place the resolver.
    var displayLine: String {
        var line = ip
        if let operatorName, !operatorName.isEmpty { line += " — \(operatorName)" }
        if let short = shortLocation { line += " (\(short))" }
        if let transport, !transport.isEmpty { line += " · \(transport)" }
        return line
    }

    /// "Berlin, State of Berlin, DE" → "Berlin, DE"; anything with fewer than three components
    /// is already short enough and passes through untouched. Note that this keeps only the FIRST
    /// and LAST component of a longer list, dropping any middle ones — theoretical, since the
    /// service's format is "City, Region, CC", but it would silently lose a fourth field.
    var shortLocation: String? {
        guard let location else { return nil }
        let parts = location.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.count < 3 ? parts.joined(separator: ", ") : "\(parts[0]), \(parts[parts.count - 1])"
    }
}

/// Enumerates ALL egress resolvers, not just the one a single lookup happens to hit. Public
/// resolvers are load-balanced across a pool, so one query reveals one member — the
/// dnsleaktest.com mechanism is a ROUND of queries with unique random names (each name is
/// uncacheable, so every one traverses the full recursive chain) against a domain whose
/// authoritative server reports who asked. dnscheck.tools operates such a server; its TXT
/// answer is a set of `KEY: value` strings whose ORDER VARIES between responses, hence the
/// prefix-matching parser below. Query transport is `DNSEgressProbe.queryTXT` — same
/// mDNSResponder path, so this sees exactly what real apps' lookups experience.
public struct DNSEgressEnumerator: Sendable {
    let deadline: Double
    /// Queries per round. Six is the dnsleaktest.com convention and empirically enough to
    /// surface a pool's distinct members (typically 2+, e.g. one IPv4 and one IPv6 egress of
    /// the same operator) without turning a refresh into a burst.
    public static let roundSize = 6
    static let zone = "test.dnscheck.tools"
    public init(deadlineSeconds: Double = 3) { deadline = deadlineSeconds }

    /// Fires `queryCount` lookups in parallel, each under its own timeout. Partial failures are
    /// normal and fine — whatever answered is returned; a total failure (service down, DNS
    /// blocked) returns [] rather than throwing, so callers keep a single no-data path.
    public func enumerate(queryCount: Int = roundSize) async -> [EgressResolver] {
        guard queryCount > 0 else { return [] }
        let answers = await withTaskGroup(of: EgressResolver?.self) { group -> [EgressResolver] in
            for _ in 0..<queryCount {
                group.addTask { [deadline] in
                    let strings = await DNSEgressProbe.queryTXT(name: Self.queryName(), timeout: deadline)
                    return Self.parse(txtStrings: strings)
                }
            }
            var out: [EgressResolver] = []
            for await answer in group { if let answer { out.append(answer) } }
            return out
        }
        // Results arrive in completion order, so dedupe's "keep the first" is arbitrary between
        // two answers naming the SAME ip — they carry identical attribution by construction, and
        // the sort below makes the returned order deterministic regardless.
        let resolvers = Self.normalize(answers)
        Log.dns.debug("DNSEgressEnumerator: \(queryCount, privacy: .public) queries -> \(resolvers.map(\.ip).joined(separator: ","), privacy: .public)")
        return resolvers
    }

    /// PURE. Matches on prefixes, never positions: the answer's strings arrive in a different
    /// order on nearly every response. `FROM:` is the only load-bearing one — without a parseable
    /// IP there is no observation at all. `ID:`/`EDNS:` are ignored by design.
    static func parse(txtStrings: [String]) -> EgressResolver? {
        var resolver: EgressResolver?
        var transport: String?
        for s in txtStrings {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("FROM:") {
                resolver = parseFrom(String(t.dropFirst("FROM:".count)))
            } else if t.hasPrefix("PROTO:") {
                // "TLS AES_128_GCM_SHA256 X25519" → "TLS": the transport is the fact, the cipher
                // suite is noise for a menu row.
                transport = String(t.dropFirst("PROTO:".count))
                    .split(separator: " ", omittingEmptySubsequences: true).first.map(String.init)
            }
        }
        guard var resolver else { return nil }
        resolver.transport = transport
        return resolver
    }

    /// PURE. "74.80.89.244#39071 WoodyNet, Inc. (Berlin, State of Berlin, DE)" — address token
    /// first, then a free-form operator name that may itself contain commas and periods, then an
    /// optional parenthesized location. The location is taken as the LAST parenthesized group so
    /// an operator name carrying its own parens can't steal it; the port is split at the LAST
    /// "#" so an IPv6 literal's colons are never mistaken for a separator.
    static func parseFrom(_ body: String) -> EgressResolver? {
        let body = body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        var address = parts[0]
        var port: Int?
        if let hash = address.lastIndex(of: "#") {
            port = Int(address[address.index(after: hash)...])
            address = String(address[..<hash])
        }
        guard RelayRanges.ipv4ToUInt32(address) != nil || StackPinnedIP.isValidIPv6(address) else { return nil }
        var operatorName: String?
        var location: String?
        if parts.count > 1 {
            var rest = parts[1].trimmingCharacters(in: .whitespaces)
            if rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
                let inner = rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]
                    .trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty { location = inner }
                rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            }
            if !rest.isEmpty { operatorName = rest }
        }
        return EgressResolver(ip: address, port: port, operatorName: operatorName, location: location)
    }

    /// PURE. Dedupe by IP (one pool member can answer several of the round's queries), then
    /// order deterministically: IPv4 first — it's the stack most leaks happen on and the one the
    /// leak verdict judges primarily — and lexicographically within each family.
    static func normalize(_ resolvers: [EgressResolver]) -> [EgressResolver] {
        var seen = Set<String>()
        let unique = resolvers.filter { seen.insert($0.ip).inserted }
        return unique.sorted { a, b in
            let a6 = a.ip.contains(":"), b6 = b.ip.contains(":")
            if a6 != b6 { return !a6 }
            return a.ip < b.ip
        }
    }

    /// A fresh random name per query — the cache buster. Anything already resolved would be
    /// answered from a cache without ever reaching dnscheck.tools' authoritative server, which
    /// is exactly the observation we need.
    static func queryName() -> String { "\(randomLabel()).\(zone)" }

    /// 8 lowercase hex chars from the system RNG (2^32 values — collisions across a six-query
    /// round are negligible, and a collision would only cost one duplicate observation anyway).
    static func randomLabel() -> String {
        String(format: "%08x", UInt32.random(in: 0...UInt32.max))
    }
}
