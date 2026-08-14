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
                            provider: "ipwho.is", fetchedAt: now)
        },
        GeoEndpoint(name: "ipapi.co", url: URL(string: "https://ipapi.co/json/")!) { data, now in
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let ip = o["ip"] as? String else { throw BadResponse() }
            return ExitInfo(ip: ip, countryCode: o["country_code"] as? String, city: o["city"] as? String,
                            org: o["org"] as? String, provider: "ipapi.co", fetchedAt: now)
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
    public func lookup(ip: String, now: Date = Date()) async -> ExitInfo? {
        guard let url = URL(string: "https://ipwho.is/\(ip)") else { return nil }
        let info = await get(url, parse: Self.endpoints[0].parse, now: now)
        if let info {
            Log.geo.debug("lookup \(ip, privacy: .public): success country=\(info.countryCode ?? "nil", privacy: .public)")
        } else {
            Log.geo.debug("lookup \(ip, privacy: .public): failure")
        }
        return info
    }
}
