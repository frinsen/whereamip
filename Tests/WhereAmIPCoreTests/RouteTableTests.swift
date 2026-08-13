import XCTest
@testable import WhereAmIPCore

final class RouteTableTests: XCTestCase {
    /// Build one IPv4 route message: rt_msghdr + sockaddr_in(dst) + sockaddr_in(gateway) + sockaddr_in(netmask)
    func routeMessage(dst: String, mask: String) -> Data {
        func sockaddrIn(_ ip: String) -> Data {
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)   // 16
            sin.sin_family = sa_family_t(AF_INET)
            inet_pton(AF_INET, ip, &sin.sin_addr)
            return withUnsafeBytes(of: &sin) { Data($0) }
        }
        var hdr = rt_msghdr()
        hdr.rtm_version = UInt8(RTM_VERSION)
        hdr.rtm_type = UInt8(RTM_GET)
        hdr.rtm_addrs = RTA_DST | RTA_GATEWAY | RTA_NETMASK
        let body = sockaddrIn(dst) + sockaddrIn("192.168.1.1") + sockaddrIn(mask)
        hdr.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + body.count)
        var data = withUnsafeBytes(of: &hdr) { Data($0) }
        data.append(body)
        return data
    }
    func testHijackPairDetected() {
        let dump = routeMessage(dst: "0.0.0.0", mask: "128.0.0.0")
                 + routeMessage(dst: "128.0.0.0", mask: "128.0.0.0")
                 + routeMessage(dst: "192.168.1.0", mask: "255.255.255.0")
        XCTAssertTrue(RouteTable.hijackPairPresent(dump: dump))
    }
    func testHalfPairIsNotHijack() {
        let dump = routeMessage(dst: "0.0.0.0", mask: "128.0.0.0")
        XCTAssertFalse(RouteTable.hijackPairPresent(dump: dump))
    }
    func testNormalDefaultRouteIsNotHijack() {
        let dump = routeMessage(dst: "0.0.0.0", mask: "0.0.0.0")
                 + routeMessage(dst: "192.168.1.0", mask: "255.255.255.0")
        XCTAssertFalse(RouteTable.hijackPairPresent(dump: dump))
    }
    func testEmptyAndGarbageAreSafe() {
        XCTAssertFalse(RouteTable.hijackPairPresent(dump: Data()))
        XCTAssertFalse(RouteTable.hijackPairPresent(dump: Data([0x01, 0x02, 0x03])))
    }
    func testLiveDumpParsesWithoutCrashing() {
        // smoke: live systems always have routes; parser must at least not crash on real data
        if let dump = RouteTable.liveDump() {
            _ = RouteTable.hijackPairPresent(dump: dump)
        }
    }

    /// Build a route message with dst/gateway as full sockaddr_in structs, but the netmask
    /// as a kernel-style *truncated* sockaddr: real route sockets truncate a netmask sockaddr
    /// after its last nonzero byte (e.g. 128.0.0.0 arrives as sa_len=5, bytes [5,0,0,0,0x80]),
    /// then the whole message pads that sockaddr out to the 4-byte roundup boundary. This
    /// mirrors production data, unlike `routeMessage`'s full 16-byte sockaddr_in netmasks.
    func routeMessageTruncatedMask(dst: String, maskBytes: [UInt8]) -> Data {
        func sockaddrIn(_ ip: String) -> Data {
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            inet_pton(AF_INET, ip, &sin.sin_addr)
            return withUnsafeBytes(of: &sin) { Data($0) }
        }
        var maskData = Data(maskBytes)
        let paddedLen = max((maskData.count + 3) & ~3, 4)
        if paddedLen > maskData.count {
            // Pad with non-zero garbage (not 0x00): a parser that ignores sa_len and reads a
            // fixed 4 address bytes would pick up this garbage and compute the wrong mask,
            // so this padding choice is what makes the test actually exercise sa_len-awareness
            // rather than passing coincidentally because zero-padding looks like "no address".
            maskData.append(Data(repeating: 0xAA, count: paddedLen - maskData.count))
        }
        var hdr = rt_msghdr()
        hdr.rtm_version = UInt8(RTM_VERSION)
        hdr.rtm_type = UInt8(RTM_GET)
        hdr.rtm_addrs = RTA_DST | RTA_GATEWAY | RTA_NETMASK
        let body = sockaddrIn(dst) + sockaddrIn("192.168.1.1") + maskData
        hdr.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + body.count)
        var data = withUnsafeBytes(of: &hdr) { Data($0) }
        data.append(body)
        return data
    }

    func testHijackPairDetectedWithKernelTruncatedNetmask() {
        // Kernel-truncated netmask encoding for 128.0.0.0: sa_len=5, bytes [5,0,0,0,0x80],
        // padded to 8 bytes on the wire. Both /1 legs use this truncated form.
        let truncatedMask128: [UInt8] = [5, 0, 0, 0, 0x80]
        let dump = routeMessageTruncatedMask(dst: "0.0.0.0", maskBytes: truncatedMask128)
                 + routeMessageTruncatedMask(dst: "128.0.0.0", maskBytes: truncatedMask128)
        XCTAssertTrue(RouteTable.hijackPairPresent(dump: dump))
    }

    func testTruncatedZeroNetmaskOnDefaultRouteIsNotHijack() {
        // A zero-length netmask sockaddr (sa_len=0) decodes to mask 0.0.0.0 — the kernel's
        // truncated encoding of a normal default route's netmask, not one leg of the /1
        // hijack pair. Must decode to 0, not garbage, and must not be mistaken for a hijack leg.
        let truncatedZeroMask: [UInt8] = [0, 0]
        let dump = routeMessageTruncatedMask(dst: "0.0.0.0", maskBytes: truncatedZeroMask)
        XCTAssertFalse(RouteTable.hijackPairPresent(dump: dump))
    }
}
