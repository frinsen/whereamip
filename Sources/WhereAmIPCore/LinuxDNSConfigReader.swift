#if os(Linux)
import Foundation

/// Which resolvers this machine is configured to ask — the Linux side of
/// `DNSConfigReader`, producing the same model (address + the interface it is scoped to).
///
/// systemd-resolved first, because it is what Ubuntu, elementary OS, Fedora and most
/// desktops run, and because it is the only source that knows the per-link picture (Wi-Fi's
/// router, the tunnel's own resolver) — `/etc/resolv.conf` on those systems names nothing
/// but resolved's local stub. Plain `resolv.conf` is the fallback for systems without it.
enum LinuxDNSConfigReader {
    /// resolved's stub listener: a forwarding hop on this machine, never the answer to
    /// "which resolver do I use".
    static let resolvedStubs: Set<String> = ["127.0.0.53", "127.0.0.54"]

    static func snapshot() -> (resolvers: [DNSResolver], encryption: DNSEncryption) {
        if let dns = LinuxSystem.run("resolvectl", ["dns"]) {
            let resolvers = parse(resolvectlDNS: dns)
            if !resolvers.isEmpty {
                let encryption = LinuxSystem.run("resolvectl", ["status"]).map(encryption(resolvectlStatus:)) ?? .unknown
                return (resolvers, encryption)
            }
        }
        let stubConf = LinuxSystem.read("/etc/resolv.conf").map(parse(resolvConf:)) ?? []
        if stubConf.isEmpty || stubConf.allSatisfy({ resolvedStubs.contains($0.address) }),
           let upstream = LinuxSystem.read("/run/systemd/resolve/resolv.conf").map(parse(resolvConf:)),
           !upstream.isEmpty {
            return (upstream, .unknown)
        }
        return (stubConf, .unknown)
    }

    /// PURE, tested. `resolvectl dns`:
    ///
    ///     Global: 1.1.1.1#cloudflare-dns.com
    ///     Link 2 (wlp2s0): 192.168.178.1 fd00::1
    ///     Link 5 (wg0): 10.64.0.1
    ///
    /// Global entries carry no interface (the macOS "global" resolvers); a link's entries
    /// are scoped to it. Unique by (address, interface), in output order — the same rules
    /// `DNSConfigReader.parse` applies to SCDynamicStore's dictionaries.
    static func parse(resolvectlDNS output: String) -> [DNSResolver] {
        var out: [DNSResolver] = []
        var seen = Set<String>()
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let interface: String?
            let servers: Substring
            if line.hasPrefix("Global:") {
                interface = nil
                servers = line.dropFirst("Global:".count)
            } else if line.hasPrefix("Link "), let open = line.firstIndex(of: "("),
                      let close = line.range(of: "):"), open < close.lowerBound {
                interface = String(line[line.index(after: open)..<close.lowerBound])
                servers = line[close.upperBound...]
            } else {
                continue
            }
            for token in servers.split(separator: " ") {
                guard let address = serverAddress(String(token)) else { continue }
                guard seen.insert("\(address)|\(interface ?? "")").inserted else { continue }
                out.append(DNSResolver(address: address, isIPv6: address.contains(":"), interface: interface))
            }
        }
        return out
    }

    /// PURE, tested. One server token as resolved prints it — `ADDR`, `ADDR:PORT`,
    /// `[V6]:PORT`, any of those with `%IFACE` and/or `#SERVERNAME` — reduced to the bare
    /// address the rest of the app compares. nil for anything that is not an IP literal.
    static func serverAddress(_ token: String) -> String? {
        var s = Substring(token)
        if let hash = s.firstIndex(of: "#") { s = s[..<hash] }
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            s = s[s.index(after: s.startIndex)..<close]
        } else if s.contains("."), s.filter({ $0 == ":" }).count == 1, let colon = s.firstIndex(of: ":") {
            s = s[..<colon]   // IPv4:PORT
        }
        let address = RouteInspector.stripZoneID(String(s))
        guard RelayRanges.ipv4ToUInt32(address) != nil || StackPinnedIP.isValidIPv6(address) else { return nil }
        return address
    }

    /// PURE, tested. `nameserver` lines of a resolv.conf; all global (no interface), since
    /// the file has no notion of scope.
    static func parse(resolvConf: String) -> [DNSResolver] {
        var out: [DNSResolver] = []
        var seen = Set<String>()
        for rawLine in resolvConf.split(separator: "\n") {
            let fields = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, fields[0] == "nameserver",
                  let address = serverAddress(String(fields[1])),
                  seen.insert(address).inserted else { continue }
            out.append(DNSResolver(address: address, isIPv6: address.contains(":")))
        }
        return out
    }

    /// PURE, tested. DNS-over-TLS in force anywhere (`+DNSOverTLS` on the global or a link's
    /// Protocols line) → `.dot`. Everything else is `.unknown`, never a guessed `.plaintext`:
    /// opportunistic mode (`DNSOverTLS=opportunistic`) may or may not be encrypting, and a
    /// local DoH/DoT forwarder (dnscrypt-proxy, cloudflared) encrypts behind a plaintext hop
    /// resolved cannot see — the same "absence is not evidence" rule the macOS reader keeps.
    static func encryption(resolvectlStatus output: String) -> DNSEncryption {
        for line in output.split(separator: "\n") where line.contains("Protocols:") {
            if line.split(separator: " ").contains("+DNSOverTLS") { return .dot }
        }
        return .unknown
    }
}
#endif
