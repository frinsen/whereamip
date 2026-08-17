import Foundation

struct BadResponse: Error {}

struct GeoEndpoint: Sendable {
    let name: String
    let url: URL
    let parse: @Sendable (Data, Date) throws -> ExitInfo
}

public struct GeoProviderChain: Sendable {
    let session: URLSession
    let deadline: Double
    public init(session: URLSession = URLSession(configuration: .default), deadlineSeconds: Double = 5) {
        self.session = session
        self.deadline = deadlineSeconds
    }

    static let endpoints: [GeoEndpoint] = [
        GeoEndpoint(name: "ipwho.is", url: URL(string: "https://ipwho.is/")!) { data, now in
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard o["success"] as? Bool == true, let ip = o["ip"] as? String else { throw BadResponse() }
            let conn = o["connection"] as? [String: Any]
            return ExitInfo(ip: ip, countryCode: o["country_code"] as? String, city: o["city"] as? String,
                            org: (conn?["org"] as? String) ?? (conn?["isp"] as? String),
                            provider: "ipwho.is", fetchedAt: now, asn: conn?["asn"] as? Int)
        },
        GeoEndpoint(name: "ipapi.co", url: URL(string: "https://ipapi.co/json/")!) { data, now in
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let ip = o["ip"] as? String else { throw BadResponse() }
            // ipapi.co's "asn" field is a string like "AS15169" — parse the digits after the
            // "AS" prefix; anything else (missing, malformed) yields nil, same as ipify's total
            // absence of ASN data. Never guess.
            let asn = (o["asn"] as? String).flatMap { s -> Int? in
                let digits = s.hasPrefix("AS") ? String(s.dropFirst(2)) : s
                return Int(digits)
            }
            return ExitInfo(ip: ip, countryCode: o["country_code"] as? String, city: o["city"] as? String,
                            org: o["org"] as? String, provider: "ipapi.co", fetchedAt: now, asn: asn)
        },
        GeoEndpoint(name: "ipify", url: URL(string: "https://api.ipify.org?format=json")!) { data, now in
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let ip = o["ip"] as? String else { throw BadResponse() }
            return ExitInfo(ip: ip, provider: "ipify", fetchedAt: now)
        },
    ]

    func get(_ url: URL, parse: @escaping @Sendable (Data, Date) throws -> ExitInfo, now: Date) async -> ExitInfo? {
        try? await withHardDeadline(seconds: deadline) { [session] in
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw BadResponse() }
            return try parse(data, now)
        }
    }
    public func fetch(now: Date = Date()) async -> ExitInfo? {
        for e in Self.endpoints {
            if let info = await get(e.url, parse: e.parse, now: now) {
                Log.geo.debug("fetch \(e.name, privacy: .public): success ip=\(info.ip, privacy: .public) country=\(info.countryCode ?? "nil", privacy: .public)")
                return info
            }
            Log.geo.debug("fetch \(e.name, privacy: .public): failure")
        }
        Log.geo.error("fetch: all geo providers failed")
        return nil
    }
    // Per-IP lookup URL builders paired with the SAME parse closures `fetch()` already uses for
    // each provider (reused verbatim — including the ASN handling for each payload shape).
    // ipify has no per-IP lookup endpoint at all, so it's not part of this chain.
    static let lookupEndpoints: [(name: String, url: (String) -> URL?, parse: @Sendable (Data, Date) throws -> ExitInfo)] = [
        (name: "ipwho.is", url: { ip in URL(string: "https://ipwho.is/\(ip)") }, parse: GeoProviderChain.endpoints[0].parse),
        (name: "ipapi.co", url: { ip in URL(string: "https://ipapi.co/\(ip)/json/") }, parse: GeoProviderChain.endpoints[1].parse),
    ]
    /// Single-IP attribution lookup (used for both stack-pinned exits and DNS-egress
    /// attribution). Was a single point of silence — ipwho.is alone, no fallback — before this
    /// fix: give it the same fallback-chain behavior class as `fetch()`, at minimum falling
    /// through to ipapi.co when ipwho.is fails, so a transient/rate-limited primary provider
    /// doesn't silently blank out ASN/org data for an entire refresh.
    public func lookup(ip: String, now: Date = Date()) async -> ExitInfo? {
        for e in Self.lookupEndpoints {
            guard let url = e.url(ip) else { continue }
            if let info = await get(url, parse: e.parse, now: now) {
                Log.geo.debug("lookup \(ip, privacy: .public): success via \(e.name, privacy: .public) country=\(info.countryCode ?? "nil", privacy: .public)")
                return info
            }
            Log.geo.debug("lookup \(ip, privacy: .public): \(e.name, privacy: .public) failed")
        }
        Log.geo.error("lookup \(ip, privacy: .public): all geo providers failed")
        return nil
    }
}
