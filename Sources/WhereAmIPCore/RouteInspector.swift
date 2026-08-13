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
        guard let (iface, localIP) = defaultRouteInterface() else {
            return RouteInfo(defaultInterface: nil, isVPN: false, vpnName: nil, hijackRoutePresent: hijack)
        }
        let isVPN = isTunnelInterface(iface)
        let scServiceName = isVPN ? SCServiceNamer.serviceName(forInterface: iface) : nil
        let name = VPNNamer.name(interface: iface, localAddress: localIP,
                                 scServiceName: scServiceName, runningBundleIDs: runningBundleIDs)
        return RouteInfo(defaultInterface: iface, isVPN: isVPN, vpnName: name, hijackRoutePresent: hijack)
    }
}
