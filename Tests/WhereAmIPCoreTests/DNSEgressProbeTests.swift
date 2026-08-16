import XCTest
@testable import WhereAmIPCore

final class DNSEgressProbeTests: XCTestCase {
    func testParseBareIPv4() {
        XCTAssertEqual(DNSEgressProbe.parseAnswer(txtStrings: ["203.0.113.7"])?.ip, "203.0.113.7")
        XCTAssertEqual(DNSEgressProbe.parseAnswer(txtStrings: ["203.0.113.7"])?.isIPv6, false)
    }
    func testParseBareIPv6() {
        let r = DNSEgressProbe.parseAnswer(txtStrings: ["2a00:1450::5"])
        XCTAssertEqual(r?.ip, "2a00:1450::5"); XCTAssertEqual(r?.isIPv6, true)
    }
    func testParsePrefersBareIPOverECS() {
        let r = DNSEgressProbe.parseAnswer(txtStrings: ["edns0-client-subnet 1.2.3.0/24", "203.0.113.7"])
        XCTAssertEqual(r?.ip, "203.0.113.7")
    }
    func testParseECSFallback() {
        let r = DNSEgressProbe.parseAnswer(txtStrings: ["edns0-client-subnet 1.2.3.0/24"])
        XCTAssertEqual(r?.ip, "1.2.3.0/24"); XCTAssertEqual(r?.isIPv6, false)
    }
    func testParseGarbageIsNil() {
        XCTAssertNil(DNSEgressProbe.parseAnswer(txtStrings: ["hello", ""]))
        XCTAssertNil(DNSEgressProbe.parseAnswer(txtStrings: []))
    }
    func testTXTRDataDecoding() {
        // TXT rdata: length-prefixed character-strings. "abc" + "de"
        let rdata = Data([3, 0x61, 0x62, 0x63, 2, 0x64, 0x65])
        XCTAssertEqual(DNSEgressProbe.parseTXTRData(rdata), ["abc", "de"])
        XCTAssertEqual(DNSEgressProbe.parseTXTRData(Data([200, 0x61])), [])  // truncated → skip, no crash
    }
}
