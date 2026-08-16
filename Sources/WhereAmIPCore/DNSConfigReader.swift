import Foundation
import SystemConfiguration

/// Raw SCDynamicStore DNS dictionaries, keyed by store key — the syscall boundary returns
/// dumb data so `parse` stays pure and fixture-testable (the RouteTable.liveDump pattern).
public struct DNSRawConfig {
    public var global: [String: Any]?                  // State:/Network/Global/DNS
    public var serviceDNS: [String: [String: Any]]     // serviceID → State:/Network/Service/<id>/DNS
    public var serviceIPv4: [String: [String: Any]]    // serviceID → .../IPv4 (for InterfaceName)
    public init(global: [String: Any]? = nil,
                serviceDNS: [String: [String: Any]] = [:],
                serviceIPv4: [String: [String: Any]] = [:]) {
        self.global = global; self.serviceDNS = serviceDNS; self.serviceIPv4 = serviceIPv4
    }
}

public enum DNSConfigReader {
    /// IMPURE: one SCDynamicStore read (mirrors SCServiceNamer's store usage).
    public static func snapshotRaw() -> DNSRawConfig {
        guard let store = SCDynamicStoreCreate(nil, "whereamip-dns" as CFString, nil, nil) else {
            return DNSRawConfig()
        }
        var raw = DNSRawConfig()
        raw.global = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        if let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/DNS" as CFString) as? [String] {
            for key in keys {
                // key: State:/Network/Service/<UUID>/DNS
                let parts = key.split(separator: "/")
                guard parts.count >= 4 else { continue }
                let id = String(parts[3])
                if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                    raw.serviceDNS[id] = dict
                }
                let v4Key = "State:/Network/Service/\(id)/IPv4"
                if let v4 = SCDynamicStoreCopyValue(store, v4Key as CFString) as? [String: Any] {
                    raw.serviceIPv4[id] = v4
                }
            }
        }
        return raw
    }

    /// PURE: raw dictionaries → model. Unique by (address, interface); global first, then
    /// scoped services in deterministic (sorted-ID) order.
    public static func parse(_ raw: DNSRawConfig) -> (resolvers: [DNSResolver], encryption: DNSEncryption) {
        var out: [DNSResolver] = []
        var seen = Set<String>()
        func add(_ addr: String, interface: String?) {
            guard !addr.isEmpty else { return }
            let a = RouteInspector.stripZoneID(addr)
            let key = "\(a)|\(interface ?? "")"
            guard seen.insert(key).inserted else { return }
            out.append(DNSResolver(address: a, isIPv6: a.contains(":"), interface: interface))
        }
        for case let addr as String in (raw.global?["ServerAddresses"] as? [Any]) ?? [] {
            add(addr, interface: nil)
        }
        for (id, dns) in raw.serviceDNS.sorted(by: { $0.key < $1.key }) {
            // Field-observed on a live utun VPN service: no matching State:/.../IPv4 entry
            // existed at all, but the DNS dict itself carried "InterfaceName" alongside
            // ServerAddresses — fall back to it rather than losing the attribution.
            let iface = (raw.serviceIPv4[id]?["InterfaceName"] as? String) ?? (dns["InterfaceName"] as? String)
            for case let addr as String in (dns["ServerAddresses"] as? [Any]) ?? [] {
                add(addr, interface: iface)
            }
        }
        return (out, encryption(raw))
    }

    /// Best-effort: an encrypted-DNS profile surfaces ServerURL (DoH) / ServerName (DoT) in
    /// the DNS dictionaries. Until the DoH fixture-capture confirms absence reliably means
    /// plaintext, absent signal → .unknown, never a guessed .plaintext (spec rule).
    static func encryption(_ raw: DNSRawConfig) -> DNSEncryption {
        let dicts = [raw.global].compactMap { $0 } + Array(raw.serviceDNS.values)
        if dicts.contains(where: { $0["ServerURL"] != nil }) { return .doh }
        if dicts.contains(where: { $0["ServerName"] != nil }) { return .dot }
        return .unknown
    }
}

public struct LiveDNSConfigReader: Sendable {
    public init() {}
    public func snapshot() -> (resolvers: [DNSResolver], encryption: DNSEncryption) {
        DNSConfigReader.parse(DNSConfigReader.snapshotRaw())
    }
}
