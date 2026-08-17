import XCTest
@testable import WhereAmIPCore

final class SCServiceNamerTests: XCTestCase {
    func testMatchesViaDNSKeyOnly() {
        // The field-verified NE-tunnel shape: no IPv4 candidate at all, InterfaceName only
        // present under the DNS key.
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network/Service/ABC-123/DNS", ["InterfaceName": "utun16", "ServerAddresses": ["100.100.100.100"]]),
        ]
        XCTAssertEqual(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "utun16"), "ABC-123")
    }

    func testMatchesViaIPv6KeyOnly() {
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network/Service/DEF-456/IPv6", ["InterfaceName": "utun5"]),
        ]
        XCTAssertEqual(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "utun5"), "DEF-456")
    }

    func testDedupesWhenSameServiceMatchesMultipleKeys() {
        // Same service UUID appears under both IPv6 and DNS with a matching InterfaceName —
        // must still resolve to exactly one service id (the first one scanned), not error or
        // ambiguity.
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network/Service/GHI-789/IPv6", ["InterfaceName": "utun7"]),
            ("State:/Network/Service/GHI-789/DNS", ["InterfaceName": "utun7"]),
        ]
        XCTAssertEqual(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "utun7"), "GHI-789")
    }

    func testFirstMatchWinsOverLaterService() {
        // Two different services both happen to report the same interface name (shouldn't
        // really happen, but the contract is well-defined regardless): the first one
        // encountered, scanning in caller order, wins.
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network/Service/FIRST-1/IPv4", ["InterfaceName": "en0"]),
            ("State:/Network/Service/SECOND-2/IPv4", ["InterfaceName": "en0"]),
        ]
        XCTAssertEqual(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "en0"), "FIRST-1")
    }

    func testNoMatchReturnsNil() {
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network/Service/XYZ-000/IPv4", ["InterfaceName": "en0"]),
        ]
        XCTAssertNil(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "utun9"))
    }

    func testMalformedKeyIsSkipped() {
        // Too few path components to extract a service UUID — must be skipped, not crash.
        let candidates: [(key: String, dict: [String: Any])] = [
            ("State:/Network", ["InterfaceName": "utun2"]),
        ]
        XCTAssertNil(SCServiceNamer.matchingServiceID(candidates: candidates, interface: "utun2"))
    }

    func testEmptyCandidatesReturnsNil() {
        XCTAssertNil(SCServiceNamer.matchingServiceID(candidates: [], interface: "utun0"))
    }
}
