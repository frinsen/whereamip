import Foundation

public enum Connectivity: String, Equatable, Codable, Sendable { case online, offline, checking }

public struct ExitInfo: Equatable, Codable, Sendable {
    public var ip: String
    public var countryCode: String?
    public var city: String?
    public var org: String?
    public var provider: String
    public var fetchedAt: Date
    public init(ip: String, countryCode: String? = nil, city: String? = nil,
                org: String? = nil, provider: String, fetchedAt: Date) {
        self.ip = ip
        self.countryCode = countryCode
        self.city = city
        self.org = org
        self.provider = provider
        self.fetchedAt = fetchedAt
    }
}

public struct RouteInfo: Equatable, Codable, Sendable {
    public var defaultInterface: String?
    public var isVPN: Bool
    public var vpnName: String?
    public var hijackRoutePresent: Bool
    public init(defaultInterface: String? = nil, isVPN: Bool = false,
                vpnName: String? = nil, hijackRoutePresent: Bool = false) {
        self.defaultInterface = defaultInterface
        self.isVPN = isVPN
        self.vpnName = vpnName
        self.hijackRoutePresent = hijackRoutePresent
    }
}

public enum PrivateRelay: Equatable, Codable, Sendable {
    case active(egressIP: String?, egressCountry: String?)
    case inactive
    case unknown
}

extension PrivateRelay {
    private enum CodingKeys: String, CodingKey { case status, egressIP, egressCountry }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "active": self = .active(egressIP: try c.decodeIfPresent(String.self, forKey: .egressIP),
                                      egressCountry: try c.decodeIfPresent(String.self, forKey: .egressCountry))
        case "inactive": self = .inactive
        default: self = .unknown
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .active(let ip, let country):
            try c.encode("active", forKey: .status)
            try c.encodeIfPresent(ip, forKey: .egressIP)
            try c.encodeIfPresent(country, forKey: .egressCountry)
        case .inactive: try c.encode("inactive", forKey: .status)
        case .unknown: try c.encode("unknown", forKey: .status)
        }
    }
}

public struct ExitState: Equatable, Codable, Sendable {
    public var connectivity: Connectivity
    public var exit: ExitInfo?
    public var route: RouteInfo
    public var privateRelay: PrivateRelay
    public var since: Date
    public init(connectivity: Connectivity = .checking, exit: ExitInfo? = nil,
                route: RouteInfo = RouteInfo(), privateRelay: PrivateRelay = .unknown,
                since: Date = Date()) {
        self.connectivity = connectivity
        self.exit = exit
        self.route = route
        self.privateRelay = privateRelay
        self.since = since
    }
}

public enum MenuBarStyle: String, CaseIterable, Codable, Sendable { case emoji, code, image }

public enum Glyph: Equatable {
    case text(String)          // emoji flag or ISO code
    case symbol(String)        // SF Symbol name (template)
    case flagImage(iso: String) // lowercase iso for PNG asset lookup
}

public extension ExitState {
    func glyph(style: MenuBarStyle) -> Glyph {
        if connectivity == .offline { return .symbol("wifi.slash") }
        guard let iso = exit?.countryCode, let emoji = Flags.emoji(countryCode: iso) else {
            return .symbol("questionmark")
        }
        switch style {
        case .emoji: return .text(emoji)
        case .code:  return .text(iso.uppercased())
        case .image: return .flagImage(iso: iso.lowercased())
        }
    }
}
