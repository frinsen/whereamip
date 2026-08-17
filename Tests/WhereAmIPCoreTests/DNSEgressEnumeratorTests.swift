import XCTest
@testable import WhereAmIPCore

final class DNSEgressEnumeratorTests: XCTestCase {
    // Two live answers captured from this machine on 2026-08-17 — same query shape, DIFFERENT
    // string order, different transports. Order variance is the whole reason `parse` matches on
    // prefixes instead of positions.
    let v6Answer = ["FROM: 2620:171:57:f003:9999::244#21315 WoodyNet, Inc. (Berlin, State of Berlin, DE)",
                    "PROTO: UDP", "ID: 37350", "EDNS: flags: do; udp: 1232"]
    let v4Answer = ["ID: 117", "PROTO: TLS AES_128_GCM_SHA256 X25519",
                    "FROM: 74.80.89.244#39071 WoodyNet, Inc. (Berlin, State of Berlin, DE)",
                    "EDNS: flags: do; udp: 1232"]

    // MARK: - parse

    func testParsesIPv6AnswerWithPortOperatorAndLocation() {
        let r = DNSEgressEnumerator.parse(txtStrings: v6Answer)
        XCTAssertEqual(r?.ip, "2620:171:57:f003:9999::244")
        XCTAssertEqual(r?.port, 21315)
        XCTAssertEqual(r?.operatorName, "WoodyNet, Inc.")
        XCTAssertEqual(r?.location, "Berlin, State of Berlin, DE")
        XCTAssertEqual(r?.transport, "UDP")
    }
    func testParsesIPv4AnswerRegardlessOfStringOrder() {
        let r = DNSEgressEnumerator.parse(txtStrings: v4Answer)
        XCTAssertEqual(r?.ip, "74.80.89.244")
        XCTAssertEqual(r?.port, 39071)
        XCTAssertEqual(r?.operatorName, "WoodyNet, Inc.", "operator names contain commas and periods")
        XCTAssertEqual(r?.transport, "TLS", "cipher suite details after the transport are dropped")
    }
    func testParseIsOrderIndependent() {
        XCTAssertEqual(DNSEgressEnumerator.parse(txtStrings: v6Answer),
                       DNSEgressEnumerator.parse(txtStrings: v6Answer.reversed()))
    }
    func testParseWithoutProtoStringLeavesTransportNil() {
        let r = DNSEgressEnumerator.parse(txtStrings: ["FROM: 74.80.89.244#39071 WoodyNet, Inc. (Berlin, DE)"])
        XCTAssertEqual(r?.ip, "74.80.89.244")
        XCTAssertNil(r?.transport)
    }
    func testParseWithoutPortOperatorOrLocation() {
        let r = DNSEgressEnumerator.parse(txtStrings: ["FROM: 9.9.9.9", "PROTO: TCP"])
        XCTAssertEqual(r?.ip, "9.9.9.9")
        XCTAssertNil(r?.port)
        XCTAssertNil(r?.operatorName)
        XCTAssertNil(r?.location)
        XCTAssertEqual(r?.transport, "TCP")
    }
    func testParseOperatorWithoutLocationParens() {
        let r = DNSEgressEnumerator.parse(txtStrings: ["FROM: 9.9.9.9#53 Quad9"])
        XCTAssertEqual(r?.operatorName, "Quad9")
        XCTAssertNil(r?.location)
    }
    func testParseGarbageIsNil() {
        XCTAssertNil(DNSEgressEnumerator.parse(txtStrings: []))
        XCTAssertNil(DNSEgressEnumerator.parse(txtStrings: ["hello", "", "PROTO: UDP"]))
        XCTAssertNil(DNSEgressEnumerator.parse(txtStrings: ["FROM: not-an-ip#53 Someone (Berlin, DE)"]),
                     "a FROM string whose address is not an IP literal carries no usable fact")
        XCTAssertNil(DNSEgressEnumerator.parse(txtStrings: ["FROM:"]))
    }

    // MARK: - dedupe + sort

    func makeResolver(_ ip: String, op: String? = nil) -> EgressResolver {
        EgressResolver(ip: ip, operatorName: op)
    }
    func testNormalizeDedupesByIPKeepingFirst() {
        let out = DNSEgressEnumerator.normalize([makeResolver("9.9.9.9", op: "Quad9"),
                                                 makeResolver("9.9.9.9", op: "Quad9 again")])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.operatorName, "Quad9")
    }
    func testNormalizeSortsIPv4BeforeIPv6ThenLexicographically() {
        let out = DNSEgressEnumerator.normalize([makeResolver("2620:171::244"), makeResolver("74.80.89.244"),
                                                 makeResolver("2001:db8::1"), makeResolver("1.1.1.1")])
        XCTAssertEqual(out.map(\.ip), ["1.1.1.1", "74.80.89.244", "2001:db8::1", "2620:171::244"])
    }
    func testNormalizeOfEmptyIsEmpty() {
        XCTAssertTrue(DNSEgressEnumerator.normalize([]).isEmpty)
    }

    // MARK: - random cache-busting label

    func testRandomLabelIsEightHexCharsAndVaries() {
        let labels = (0..<200).map { _ in DNSEgressEnumerator.randomLabel() }
        for l in labels {
            XCTAssertEqual(l.count, 8)
            XCTAssertTrue(l.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
        // Cache busting only works if the labels actually differ; 200 draws from 2^32 colliding
        // into fewer than 190 distinct values would mean the generator is broken, not unlucky.
        XCTAssertGreaterThan(Set(labels).count, 190)
    }
    func testQueryNameIsARandomLabelUnderTheDNSCheckZone() {
        let name = DNSEgressEnumerator.queryName()
        XCTAssertTrue(name.hasSuffix(".test.dnscheck.tools"), "got: \(name)")
        XCTAssertEqual(name.split(separator: ".").count, 4)
        XCTAssertNotEqual(name, DNSEgressEnumerator.queryName())
    }

    // MARK: - display formatting (shared by the dropdown and the CLI)

    func testDisplayLineWithEveryPart() {
        let r = EgressResolver(ip: "185.44.108.99", port: 39071, operatorName: "WoodyNet, Inc.",
                               location: "Berlin, State of Berlin, DE", transport: "UDP")
        XCTAssertEqual(r.displayLine, "185.44.108.99 — WoodyNet, Inc. (Berlin, DE) · UDP")
    }
    func testDisplayLineOmitsMissingParts() {
        XCTAssertEqual(EgressResolver(ip: "9.9.9.9").displayLine, "9.9.9.9")
        XCTAssertEqual(EgressResolver(ip: "9.9.9.9", operatorName: "Quad9").displayLine, "9.9.9.9 — Quad9")
        XCTAssertEqual(EgressResolver(ip: "9.9.9.9", transport: "TCP").displayLine, "9.9.9.9 · TCP")
        XCTAssertEqual(EgressResolver(ip: "9.9.9.9", location: "Zurich, CH").displayLine, "9.9.9.9 (Zurich, CH)")
    }
    func testDisplayLineKeepsTwoPartLocationsIntact() {
        let r = EgressResolver(ip: "9.9.9.9", location: "Zurich, CH")
        XCTAssertEqual(r.displayLine, "9.9.9.9 (Zurich, CH)", "only the middle region is dropped, never the city or CC")
    }
}
