import XCTest
@testable import WhereAmIPCore

final class DNSConfigReaderTests: XCTestCase {
    func testGlobalOnlyConfig() {
        let raw = DNSRawConfig(global: ["ServerAddresses": ["192.168.1.1", "9.9.9.9"]])
        let (resolvers, enc) = DNSConfigReader.parse(raw)
        XCTAssertEqual(resolvers.map(\.address), ["192.168.1.1", "9.9.9.9"])
        XCTAssertEqual(resolvers.map(\.interface), [nil, nil])
        XCTAssertEqual(enc, .unknown)
    }

    func testScopedVPNResolversAttributedToInterface() {
        let raw = DNSRawConfig(
            global: ["ServerAddresses": ["192.168.1.1"]],
            serviceDNS: ["AAAA-1111": ["ServerAddresses": ["10.8.0.1"]]],
            serviceIPv4: ["AAAA-1111": ["InterfaceName": "utun13"]])
        let (resolvers, _) = DNSConfigReader.parse(raw)
        XCTAssertEqual(resolvers.count, 2)
        XCTAssertEqual(resolvers[0], DNSResolver(address: "192.168.1.1", isIPv6: false, interface: nil))
        XCTAssertEqual(resolvers[1], DNSResolver(address: "10.8.0.1", isIPv6: false, interface: "utun13"))
    }

    func testLinkLocalV6ZoneStrippedAndFlagged() {
        let raw = DNSRawConfig(global: ["ServerAddresses": ["fe80::1%en0"]])
        let (resolvers, _) = DNSConfigReader.parse(raw)
        XCTAssertEqual(resolvers, [DNSResolver(address: "fe80::1", isIPv6: true, interface: nil)])
    }

    func testDuplicateAddressSameScopeDeduped() {
        let raw = DNSRawConfig(global: ["ServerAddresses": ["1.1.1.1", "1.1.1.1"]])
        XCTAssertEqual(DNSConfigReader.parse(raw).resolvers.count, 1)
    }

    func testDoHSignalDetected() {
        // Synthetic until the fixture-capture step below confirms the real key shape.
        let raw = DNSRawConfig(serviceDNS: ["S": ["ServerURL": "https://dns.nextdns.io/abc"]])
        XCTAssertEqual(DNSConfigReader.parse(raw).encryption, .doh)
    }

    func testDoTSignalDetected() {
        let raw = DNSRawConfig(serviceDNS: ["S": ["ServerName": "one.one.one.one"]])
        XCTAssertEqual(DNSConfigReader.parse(raw).encryption, .dot)
    }

    func testNoSignalMeansUnknownNeverPlaintext() {
        XCTAssertEqual(DNSConfigReader.parse(DNSRawConfig()).encryption, .unknown)
    }

    func testGarbageIsSkippedWithoutCrash() {
        let raw = DNSRawConfig(global: ["ServerAddresses": [42, ""] as [Any]],
                               serviceDNS: ["S": ["nonsense": true]])
        XCTAssertEqual(DNSConfigReader.parse(raw).resolvers, [])
    }
}
