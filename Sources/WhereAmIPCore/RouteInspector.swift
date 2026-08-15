import Foundation

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
    private static func stripZoneID(_ s: String) -> String {
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
        let name = VPNNamer.name(interface: iface, localAddress: localIP,
                                 scServiceName: scServiceName, runningBundleIDs: runningBundleIDs)
        Log.route.debug("snapshot: interface=\(iface, privacy: .public) isVPN=\(isVPN, privacy: .public) vpnName=\(name ?? "nil", privacy: .public)")
        return RouteInfo(defaultInterface: iface, isVPN: isVPN, vpnName: name, hijackRoutePresent: hijack,
                         v6DefaultInterface: v6?.interface, v6IsVPN: v6IsVPN)
    }
}
