import Foundation

/// Stack-pinned exit-IP discovery: `api4.ipify.org` has only an A record (so a request to it
/// is forced over IPv4) and `api6.ipify.org` has only an AAAA record (forced over IPv6).
/// Hitting these two hosts independently is what makes dual-stack leak detection possible —
/// it tells us the exit IP as seen on *each* protocol family, rather than whichever family
/// happens to win when a single dual-stack host is queried.
///
/// Deliberately HTTPS, not plain HTTP (unlike `HTTPIPFetcher`, which is intentionally plain
/// HTTP so iCloud Private Relay's HTTPS-only interception reveals its egress point). Here we
/// want the opposite: this measurement must reflect exactly what the user's real HTTPS traffic
/// sees. A plain-HTTP probe would risk Private Relay (or a captive portal, or any transparent
/// proxy) intercepting it and reporting an egress IP that has nothing to do with the actual
/// v4/v6 leak this feature is trying to detect — so both requests go out over HTTPS like every
/// other real connection an app makes.
public struct StackPinnedIP: Sendable {
    let session: URLSession
    let deadline: Double
    static let url4 = URL(string: "https://api4.ipify.org")!
    static let url6 = URL(string: "https://api6.ipify.org")!

    public init(session: URLSession = URLSession(configuration: .default), deadlineSeconds: Double = 4) {
        self.session = session
        self.deadline = deadlineSeconds
    }

    /// The exit IP as seen over IPv4, or nil on any failure (bad status, unparseable body,
    /// timeout, or connection error). A nil here on an otherwise-online connection usually just
    /// means the network is IPv6-only — that's a signal, not an error, and callers must treat
    /// it as "no v4 measurement this refresh", never synthesize a leak from it.
    public func fetch4() async -> String? {
        let s = try? await withHardDeadline(seconds: deadline) { [session] in
            let (data, resp) = try await session.data(from: Self.url4)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  RelayRanges.ipv4ToUInt32(s) != nil else { throw BadResponse() }
            return s
        }
        Log.geo.debug("StackPinnedIP: fetch4=\(s ?? "nil", privacy: .public)")
        return s
    }

    /// The exit IP as seen over IPv6, or nil on any failure. A nil here on a v4-only network
    /// is the expected, common case (it's exactly how a leak-free VPN-only-tunnels-v4 setup
    /// should look) — never treat it as an error, and never let it alone imply a leak.
    public func fetch6() async -> String? {
        let s = try? await withHardDeadline(seconds: deadline) { [session] in
            let (data, resp) = try await session.data(from: Self.url6)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.isValidIPv6(s) else { throw BadResponse() }
            return s
        }
        Log.geo.debug("StackPinnedIP: fetch6=\(s ?? "nil", privacy: .public)")
        return s
    }

    /// Lenient IPv6 literal check: must contain ':' (rules out stray IPv4/garbage bodies) and
    /// parse via inet_pton — reused nowhere else since IPv4 validation already has
    /// `RelayRanges.ipv4ToUInt32` but there's no v6 equivalent in this codebase yet.
    static func isValidIPv6(_ s: String) -> Bool {
        guard s.contains(":") else { return false }
        var buf = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &buf) } == 1
    }
}
