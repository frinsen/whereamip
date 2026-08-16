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
}
