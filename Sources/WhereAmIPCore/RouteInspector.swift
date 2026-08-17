import Foundation

/// One directly connected (on-link) prefix of a local interface — the address configured on it
/// plus that address's prefix length. "Reachable without a router", which is exactly what makes
/// an address local to this machine's network segment.
public struct InterfacePrefix: Equatable, Sendable {
    public let address: String
    public let prefixLength: Int
    public init(address: String, prefixLength: Int) {
        self.address = address; self.prefixLength = prefixLength
    }
}

public enum RouteInspector {
    public static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
    }

    /// Which interface owns the IPv4 default route? Connected UDP socket to 8.8.8.8:53 — NO packet is sent
    /// (UDP connect() only queries the kernel routing table), then getsockname → local addr → getifaddrs.
    public static func defaultRouteInterface() -> (interface: String, localAddress: String)? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        inet_pton(AF_INET, "8.8.8.8", &addr.sin_addr)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let rc2 = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard rc2 == 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var sinAddr = local.sin_addr
        guard inet_ntop(AF_INET, &sinAddr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        let localIP = String(cString: buf)
        guard let iface = interfaceName(forLocalIP: localIP) else { return nil }
        return (iface, localIP)
    }

    /// Which interface owns the IPv6 default route? Same UDP-connect trick as the v4 version,
    /// using AF_INET6/sockaddr_in6 and a public IPv6 anycast address (Google DNS) as the
    /// connect() target — no packet is actually sent.
    public static func defaultRouteInterface6() -> (interface: String, localAddress: String)? {
        let fd = socket(AF_INET6, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = UInt16(53).bigEndian
        inet_pton(AF_INET6, "2001:4860:4860::8888", &addr.sin6_addr)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard rc == 0 else { return nil }
        var local = sockaddr_in6()
        var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let rc2 = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard rc2 == 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var sin6Addr = local.sin6_addr
        guard inet_ntop(AF_INET6, &sin6Addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
        let localIP = String(cString: buf)
        guard let iface = interfaceName6(forLocalIP: localIP) else { return nil }
        return (iface, localIP)
    }

    /// Strips a trailing zone/scope id (the part after '%', e.g. "fe80::1%en0") before
    /// comparing two IPv6 address strings — link-local addresses carry a scope id that can
    /// differ in formatting between getsockname()'s result and getifaddrs()'s, even when they
    /// name the same interface.
    static func stripZoneID(_ s: String) -> String {
        s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
    }

    static func interfaceName6(forLocalIP ip: String) -> String? {
        let target = stripZoneID(ip)
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET6) else { continue }
            var sin6 = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in6.self).pointee
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { continue }
            if stripZoneID(String(cString: buf)) == target { return String(cString: cur.pointee.ifa_name) }
        }
        return nil
    }

    static func interfaceName(forLocalIP ip: String) -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var sin = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in.self).pointee
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            if String(cString: buf) == ip { return String(cString: cur.pointee.ifa_name) }
        }
        return nil
    }

    /// Finds the local interface currently holding a specific IPv6 address (zone-id stripped,
    /// case-insensitive compare) — a fallback v6 egress attribution for when
    /// `defaultRouteInterface6()`'s unscoped-route lookup can't see the actual leaking
    /// interface.
    ///
    /// Field-verified root cause: PureVPN (and presumably other VPNs with similar
    /// "IPv4-only tunnel" behavior) doesn't delete the native v6 default route when its
    /// tunnel comes up — it demotes it to an interface-SCOPED route (`netstat -rn -f inet6`
    /// shows the RTF_IFSCOPE `I` flag, e.g. `default fe80::...%en0 UGcIg en0`, with no
    /// unscoped default route left at all). Apple's URLSession still happily uses scoped
    /// routes — that's exactly the app-level leak path this feature exists to catch — but our
    /// own UDP-connect trick in `defaultRouteInterface6()` only consults the *unscoped* routing
    /// table, so it comes back nil even though the leak is real.
    ///
    /// Native IPv6 has no NAT, though: whatever `exit6.ip` this refresh measured is literally
    /// present on the leaking interface as a temporary/privacy address. So when the unscoped
    /// lookup finds nothing, a direct getifaddrs address match recovers the same interface a
    /// scoped-route-aware lookup would have found — without needing to parse scoped routes at
    /// all. If the address matches no local interface (e.g. a NAT'd/tunneled v6 exit), that's
    /// the correct "can't attribute this" signal too, and callers should leave the v6 fields
    /// unset rather than guess.
    public static func interfaceHolding(ipv6 target: String) -> String? {
        let want = stripZoneID(target).lowercased()
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET6) else { continue }
            var sin6 = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in6.self).pointee
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { continue }
            if stripZoneID(String(cString: buf)).lowercased() == want { return String(cString: cur.pointee.ifa_name) }
        }
        return nil
    }

    /// Every on-link prefix this host currently has an address in — the same getifaddrs walk as
    /// the lookups above, now also reading `ifa_netmask`. Used to decide whether an address is
    /// on this machine's own network segment (see `DNSForwarderHint`), which is how a router
    /// that advertises itself with a GLOBAL address out of the ISP's delegated prefix is
    /// recognized as local without any hardcoded ISP or vendor knowledge.
    ///
    /// Deliberately excluded: loopback and down interfaces (nothing is reachable through them),
    /// zero-length prefixes (a /0 netmask would make every address on earth "local"), and IPv6
    /// link-local addresses — every interface has an fe80::/64, and fe80 is already covered by
    /// the private-range table, so including them would only add ambiguity.
    public static func localPrefixes() -> [InterfacePrefix] {
        var out: [InterfacePrefix] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sa = cur.pointee.ifa_addr, let netmask = cur.pointee.ifa_netmask else { continue }
            switch Int32(sa.pointee.sa_family) {
            case AF_INET:
                var sin = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in.self).pointee
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
                // Contiguous netmasks only (the only kind macOS configures), so a popcount over
                // the raw bytes is the prefix length regardless of byte order.
                let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
                let bits = mask.nonzeroBitCount
                if bits > 0 { out.append(InterfacePrefix(address: String(cString: buf), prefixLength: bits)) }
            case AF_INET6:
                var sin6 = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in6.self).pointee
                let isLinkLocal = withUnsafeBytes(of: sin6.sin6_addr) { $0[0] == 0xFE && $0[1] & 0xC0 == 0x80 }
                guard !isLinkLocal else { continue }
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { continue }
                let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                let bits = withUnsafeBytes(of: mask) { $0.reduce(0) { $0 + $1.nonzeroBitCount } }
                if bits > 0 {
                    out.append(InterfacePrefix(address: stripZoneID(String(cString: buf)), prefixLength: bits))
                }
            default: continue
            }
        }
        return out
    }

    public static func snapshot(runningBundleIDs: [String] = []) -> RouteInfo {
        let hijack = RouteTable.liveDump().map { RouteTable.hijackPairPresent(dump: $0) } ?? false
        if hijack {
            Log.route.error("snapshot: hijack route pair present (0.0.0.0/1 + 128.0.0.0/1)")
        }
        let v6 = defaultRouteInterface6()
        let v6IsVPN = v6.map { isTunnelInterface($0.interface) } ?? false
        Log.route.debug("snapshot: v6 interface=\(v6?.interface ?? "nil", privacy: .public) v6IsVPN=\(v6IsVPN, privacy: .public)")
        guard let (iface, localIP) = defaultRouteInterface() else {
            Log.route.debug("snapshot: no default route interface found")
            return RouteInfo(defaultInterface: nil, isVPN: false, vpnName: nil, hijackRoutePresent: hijack,
                             v6DefaultInterface: v6?.interface, v6IsVPN: v6IsVPN)
        }
        let isVPN = isTunnelInterface(iface)
        let scServiceName = isVPN ? SCServiceNamer.serviceName(forInterface: iface) : nil
        // Process scan is only worth its cost when the SC widening (A1) genuinely came up
        // empty on a tunnel — classic daemon tunnels are exactly the case scServiceName can
        // never explain, so scanning otherwise would just burn a libproc walk for nothing.
        let processNames: Set<String> = (isVPN && scServiceName == nil) ? ProcessScanner.runningProcessNames() : []
        let name = VPNNamer.name(interface: iface, localAddress: localIP,
                                 scServiceName: scServiceName, runningBundleIDs: runningBundleIDs,
                                 runningProcessNames: processNames)
        // Connection-kind display (Wave A): only meaningful for the physical/underlay
        // interface actually carrying the default route. When a VPN tunnel owns it, its
        // "kind" is the tunnel itself (already named above) — attributing that back to
        // whichever physical interface the tunnel rides over is a recorded follow-up, not
        // guessed here.
        let link = isVPN ? nil : InterfaceKind.lookup(bsdName: iface)
        Log.route.debug("snapshot: interface=\(iface, privacy: .public) isVPN=\(isVPN, privacy: .public) vpnName=\(name ?? "nil", privacy: .public) linkKind=\(link?.kind ?? "nil", privacy: .public)")
        return RouteInfo(defaultInterface: iface, isVPN: isVPN, vpnName: name, hijackRoutePresent: hijack,
                         v6DefaultInterface: v6?.interface, v6IsVPN: v6IsVPN,
                         linkKind: link?.kind, linkName: link?.displayName)
    }
}
