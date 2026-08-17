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
    // Additive (Phase 1 of the IPv6 leak detector): which interface owns the IPv6 default
    // route, and whether that interface is itself a VPN tunnel. Both default to nil/false so
    // JSON produced by pre-existing versions of this app still decodes cleanly below.
    public var v6DefaultInterface: String?
    public var v6IsVPN: Bool
    // Additive (Wave A, connection-kind display): the default-route interface's system-derived
    // kind ("Wi-Fi", "Ethernet", "iPhone USB", …) and display name, via SCNetworkInterface.
    // Populated only for non-tunnel interfaces — see RouteInspector.snapshot; both nil for VPN
    // tunnels (underlay attribution is a recorded follow-up, not guessed) and for pre-existing
    // JSON, which never had these keys — see the manual init(from:) below.
    public var linkKind: String?
    public var linkName: String?
    public init(defaultInterface: String? = nil, isVPN: Bool = false,
                vpnName: String? = nil, hijackRoutePresent: Bool = false,
                v6DefaultInterface: String? = nil, v6IsVPN: Bool = false,
                linkKind: String? = nil, linkName: String? = nil) {
        self.defaultInterface = defaultInterface
        self.isVPN = isVPN
        self.vpnName = vpnName
        self.hijackRoutePresent = hijackRoutePresent
        self.v6DefaultInterface = v6DefaultInterface
        self.v6IsVPN = v6IsVPN
        self.linkKind = linkKind
        self.linkName = linkName
    }

    private enum CodingKeys: String, CodingKey {
        case defaultInterface, isVPN, vpnName, hijackRoutePresent, v6DefaultInterface, v6IsVPN
        case linkKind, linkName
    }
    // Manual init(from:) so older JSON (missing the v6 and linkKind/linkName keys) still
    // decodes; encode(to:) is left to synthesis using the same CodingKeys, which always writes
    // the full struct.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultInterface = try c.decodeIfPresent(String.self, forKey: .defaultInterface)
        isVPN = try c.decodeIfPresent(Bool.self, forKey: .isVPN) ?? false
        vpnName = try c.decodeIfPresent(String.self, forKey: .vpnName)
        hijackRoutePresent = try c.decodeIfPresent(Bool.self, forKey: .hijackRoutePresent) ?? false
        v6DefaultInterface = try c.decodeIfPresent(String.self, forKey: .v6DefaultInterface)
        v6IsVPN = try c.decodeIfPresent(Bool.self, forKey: .v6IsVPN) ?? false
        linkKind = try c.decodeIfPresent(String.self, forKey: .linkKind)
        linkName = try c.decodeIfPresent(String.self, forKey: .linkName)
    }
}

public extension ExitInfo {
    /// "IPv4: 1.2.3.4 (Berlin, DE)" — shared dual-stack split-line formatting, used by both the
    /// CLI (`StateRenderer.human`) and the menu bar dropdown (`MenuBuilder`) so the two frontends
    /// never drift on this string. Hoisted here (rather than duplicated in each UI layer) since
    /// WhereAmIPUI already depends on WhereAmIPCore, not the other way around.
    func splitLine(label: String) -> String {
        let place = [city, countryCode].compactMap { $0 }.joined(separator: ", ")
        return "\(label): \(ip)" + (place.isEmpty ? "" : " (\(place))")
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

public struct DNSResolver: Equatable, Codable, Sendable {
    public var address: String       // zone ID already stripped: "fe80::1", never "fe80::1%en0"
    public var isIPv6: Bool
    public var interface: String?    // scoped resolver's interface; nil = global
    public init(address: String, isIPv6: Bool, interface: String? = nil) {
        self.address = address; self.isIPv6 = isIPv6; self.interface = interface
    }
}

public enum DNSEncryption: String, Equatable, Codable, Sendable { case plaintext, doh, dot, unknown }

public enum DNSLeak: String, Equatable, Codable, Sendable {
    case unknown      // no measurement — NOT a leak, NOT a clear
    case none
    case suspected    // one observed mismatch
    case confirmed    // mismatch survived a second consecutive full refresh
}

public struct DNSInfo: Equatable, Codable, Sendable {
    public var resolvers: [DNSResolver]
    public var encryption: DNSEncryption
    public var egressIP: String?          // resolver's own exit IP, or an ECS prefix like "1.2.3.0/24"
    public var egressIsIPv6: Bool
    public var measuredAt: Date?
    public var leak: DNSLeak
    public init(resolvers: [DNSResolver] = [], encryption: DNSEncryption = .unknown,
                egressIP: String? = nil, egressIsIPv6: Bool = false,
                measuredAt: Date? = nil, leak: DNSLeak = .unknown) {
        self.resolvers = resolvers; self.encryption = encryption
        self.egressIP = egressIP; self.egressIsIPv6 = egressIsIPv6
        self.measuredAt = measuredAt; self.leak = leak
    }
    // DNSConfigReader.parse deliberately dedups by (address, interface) — a global entry plus
    // one per-service entry — so the same address can appear in `resolvers` up to 3x. That's
    // correct for DNSLeakDetector's per-service attribution, but a display's "+N more" count
    // must reflect distinct addresses, not raw entry count. One source of truth shared by the
    // dropdown (MenuBuilder) and the CLI (StateRenderer.human) — same precedent as `splitLine`.
    public var uniqueAddressCount: Int {
        Set(resolvers.map(\.address)).count
    }
}

public struct ExitState: Equatable, Codable, Sendable {
    public var connectivity: Connectivity
    public var exit: ExitInfo?
    // Additive (Phase 1 of the IPv6 leak detector): the IPv6-stack-pinned exit, measured
    // independently from `exit` (which stays IPv4-primary, falling back to the geo chain
    // when a v4-pinned measurement fails). Both new fields default so pre-existing JSON
    // still decodes cleanly — see the manual init(from:) below.
    public var exit6: ExitInfo?
    public var route: RouteInfo
    public var privateRelay: PrivateRelay
    public var ipv6Leak: Bool
    public var dns: DNSInfo
    public var since: Date
    public init(connectivity: Connectivity = .checking, exit: ExitInfo? = nil, exit6: ExitInfo? = nil,
                route: RouteInfo = RouteInfo(), privateRelay: PrivateRelay = .unknown,
                ipv6Leak: Bool = false, dns: DNSInfo = DNSInfo(), since: Date = Date()) {
        self.connectivity = connectivity
        self.exit = exit
        self.exit6 = exit6
        self.route = route
        self.privateRelay = privateRelay
        self.ipv6Leak = ipv6Leak
        self.dns = dns
        self.since = since
    }

    private enum CodingKeys: String, CodingKey {
        case connectivity, exit, exit6, route, privateRelay, ipv6Leak, dns, since
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connectivity = try c.decode(Connectivity.self, forKey: .connectivity)
        exit = try c.decodeIfPresent(ExitInfo.self, forKey: .exit)
        exit6 = try c.decodeIfPresent(ExitInfo.self, forKey: .exit6)
        route = try c.decode(RouteInfo.self, forKey: .route)
        privateRelay = try c.decode(PrivateRelay.self, forKey: .privateRelay)
        ipv6Leak = try c.decodeIfPresent(Bool.self, forKey: .ipv6Leak) ?? false
        dns = try c.decodeIfPresent(DNSInfo.self, forKey: .dns) ?? DNSInfo()
        since = try c.decode(Date.self, forKey: .since)
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
