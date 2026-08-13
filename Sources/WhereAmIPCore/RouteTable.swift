import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Parses macOS `sysctl NET_RT_DUMP` route-table buffers to detect the
/// OpenVPN "redirect-gateway" hijack pattern: a split-default route pair
/// of `0.0.0.0/1` and `128.0.0.0/1` both present. When the VPN tunnel goes
/// down while these routes remain installed, all IPv4 traffic blackholes.
public enum RouteTable {
    /// Reads the live IPv4 route table via `sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0)`.
    /// Returns nil on any sysctl failure (never crashes the caller).
    public static func liveDump() -> Data? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, 6, &buf, &needed, nil, 0) == 0 else { return nil }
        return Data(buf.prefix(needed))
    }

    /// True when the dump contains both `0.0.0.0/1` (netmask 128.0.0.0) and
    /// `128.0.0.0/1` (netmask 128.0.0.0) IPv4 routes — the OpenVPN
    /// redirect-gateway split-default pattern. Never throws or crashes on
    /// truncated/garbage input; malformed messages are simply skipped.
    public static func hijackPairPresent(dump: Data) -> Bool {
        var seenHalfRoutes: Set<UInt32> = []
        let hdrSize = MemoryLayout<rt_msghdr>.size
        let rtmAddrsOffset = MemoryLayout<rt_msghdr>.offset(of: \rt_msghdr.rtm_addrs) ?? 12
        var offset = 0
        let bytes = [UInt8](dump)
        while offset + hdrSize <= bytes.count {
            // rtm_msglen is the first field (UInt16, little-endian on Darwin/arm64+x86_64).
            let msglen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            guard msglen >= hdrSize, msglen > 0, offset + msglen <= bytes.count else { break }

            let addrsFieldOffset = offset + rtmAddrsOffset
            guard addrsFieldOffset + 4 <= bytes.count else { break }
            let rtmAddrs: Int32 = dump.withUnsafeBytes { raw in
                raw.load(fromByteOffset: addrsFieldOffset, as: Int32.self)
            }

            var saOffset = offset + hdrSize
            var dst: UInt32?
            var mask: UInt32?
            // RTAX_MAX is 8 on Darwin (route.h); hardcoded in case the constant
            // isn't bridged into Swift on some SDKs.
            let rtaxMax = 8
            for bit in 0..<rtaxMax {
                let rta = Int32(1 << bit)
                guard rtmAddrs & rta != 0 else { continue }
                guard saOffset < offset + msglen, saOffset < bytes.count else { break }
                let saLen = Int(bytes[saOffset])
                guard saOffset + 2 <= bytes.count else { break }
                let family = Int32(bytes[saOffset + 1])
                if rta == RTA_DST, family == AF_INET, saLen >= 8 {
                    dst = ipv4Value(bytes, addrStart: saOffset + 4, saLen: saLen)
                }
                if rta == RTA_NETMASK {
                    // netmask sockaddrs may be truncated after the last nonzero byte
                    mask = ipv4Value(bytes, addrStart: saOffset + 4, saLen: saLen)
                }
                saOffset += max((saLen + 3) & ~3, 4)   // advance by roundup(sa_len, 4); zero-len → 4
            }
            if let d = dst, mask == 0x8000_0000, (d == 0 || d == 0x8000_0000) {
                seenHalfRoutes.insert(d)
            }
            offset += msglen
        }
        return seenHalfRoutes.contains(0) && seenHalfRoutes.contains(0x8000_0000)
    }

    /// Read up to 4 address bytes starting at addrStart, honoring a possibly-truncated sa_len.
    /// The synthetic test data builds full sockaddr_in structs (sa_len=16), while real kernel
    /// netmask sockaddrs may be truncated after the last nonzero byte — both are handled here.
    private static func ipv4Value(_ bytes: [UInt8], addrStart: Int, saLen: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 {
            let idx = addrStart + i
            let inLen = (4 + i) < saLen   // sa bytes 0..3 are len/family/port
            let byte: UInt8 = (inLen && idx < bytes.count) ? bytes[idx] : 0
            v = (v << 8) | UInt32(byte)
        }
        return v
    }
}
