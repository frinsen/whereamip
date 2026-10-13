#if os(Linux)
import Foundation

/// The OpenVPN "redirect-gateway def1" hijack check on Linux: the same split-default pair
/// (`0.0.0.0/1` + `128.0.0.0/1`) the macOS version finds in a `NET_RT_DUMP` buffer, read
/// here from `/proc/net/route` (the main IPv4 table — which is where OpenVPN installs the
/// pair; policy-routed tunnels such as wg-quick never use it).
public enum RouteTable {
    public static func liveHijackPairPresent() -> Bool {
        guard let table = LinuxSystem.read("/proc/net/route") else { return false }
        return hijackPairPresent(procNetRoute: table)
    }

    /// PURE. `/proc/net/route` lines are `Iface Destination Gateway Flags RefCnt Use Metric
    /// Mask MTU Window IRTT`, with Destination and Mask printed as the raw in-memory value of
    /// a network-byte-order address in hex (so 128.0.0.0 reads `00000080` on a
    /// little-endian machine). Header, short and garbage lines are skipped, never fatal.
    static func hijackPairPresent(procNetRoute: String) -> Bool {
        var seenHalfRoutes: Set<UInt32> = []
        for line in procNetRoute.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard fields.count >= 8,
                  let destination = UInt32(fields[1], radix: 16),
                  let mask = UInt32(fields[7], radix: 16) else { continue }
            let dst = UInt32(bigEndian: destination)
            if UInt32(bigEndian: mask) == 0x8000_0000, dst == 0 || dst == 0x8000_0000 {
                seenHalfRoutes.insert(dst)
            }
        }
        return seenHalfRoutes.contains(0) && seenHalfRoutes.contains(0x8000_0000)
    }
}
#endif
