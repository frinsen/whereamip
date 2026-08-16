import XCTest
@testable import WhereAmIPCore

final class E2EDNSConfigTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testLiveConfigParsesWithResolvers() throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        let raw = DNSConfigReader.snapshotRaw()
        let (resolvers, encryption) = DNSConfigReader.parse(raw)
        XCTAssertFalse(resolvers.isEmpty, "live system reported zero resolvers")
        // Dump raw dicts as future fixtures (the DNS spec's DoH open item).
        if let dir = env["E2E_DUMP_DIR"] {
            let dump = "GLOBAL: \(raw.global ?? [:])\nSERVICE-DNS: \(raw.serviceDNS)\nSERVICE-IPV4: \(raw.serviceIPv4)\nENCRYPTION: \(encryption)\n"
            try? dump.write(toFile: "\(dir)/dnsrawconfig-\(env["E2E_BACKEND"] ?? "unknown").txt",
                            atomically: true, encoding: .utf8)
        }
    }

    func testTailscaleScopedResolverAttributed() throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        try XCTSkipUnless(env["E2E_BACKEND"] == "tailscale")
        let (resolvers, _) = DNSConfigReader.parse(DNSConfigReader.snapshotRaw())
        let magic = resolvers.first { $0.address == "100.100.100.100" }
        XCTAssertNotNil(magic, "MagicDNS resolver not found; got \(resolvers.map(\.address))")
    }
}
