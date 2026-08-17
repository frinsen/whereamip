import XCTest
@testable import WhereAmIPCore

final class E2EDNSEgressTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testLiveEgressProbeRoundTrip() async throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        let result = await DNSEgressProbe(deadlineSeconds: 6).fetch()
        let r = try XCTUnwrap(result, "live egress probe returned nil on a working network")
        XCTAssertEqual(r.isIPv6, r.ip.contains(":"), "isIPv6 flag inconsistent with literal \(r.ip)")
        if let dir = env["E2E_DUMP_DIR"] {
            try? "egress: \(r.ip) v6=\(r.isIPv6)\n"
                .write(toFile: "\(dir)/egress-\(env["E2E_BACKEND"] ?? "unknown").txt",
                       atomically: true, encoding: .utf8)
        }
    }

    /// The round of cache-busting lookups against dnscheck.tools. Gated exactly like the probe
    /// above — the parser itself is covered offline in DNSEgressEnumeratorTests; this only
    /// proves the live service still answers in the shape we parse.
    func testLiveEgressEnumerationFindsAtLeastOneResolver() async throws {
        try XCTSkipUnless(env["WHEREAMIP_E2E"] == "1")
        let resolvers = await DNSEgressEnumerator(deadlineSeconds: 6).enumerate()
        XCTAssertFalse(resolvers.isEmpty, "live enumeration found no egress resolver on a working network")
        XCTAssertEqual(resolvers.map(\.ip).count, Set(resolvers.map(\.ip)).count, "results must be deduped by IP")
        if let dir = env["E2E_DUMP_DIR"] {
            try? (resolvers.map(\.displayLine).joined(separator: "\n") + "\n")
                .write(toFile: "\(dir)/egress-enum-\(env["E2E_BACKEND"] ?? "unknown").txt",
                       atomically: true, encoding: .utf8)
        }
    }
}
