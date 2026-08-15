import XCTest
@testable import WhereAmIPCore

final class ExitStateTests: XCTestCase {
    func makeState(_ c: Connectivity, iso: String?) -> ExitState {
        ExitState(connectivity: c,
                  exit: iso.map { ExitInfo(ip: "1.2.3.4", countryCode: $0, provider: "test", fetchedAt: Date()) },
                  since: Date())
    }
    func testOfflineBeatsEverything() {
        XCTAssertEqual(makeState(.offline, iso: "DE").glyph(style: .emoji), .symbol("wifi.slash"))
        XCTAssertEqual(makeState(.offline, iso: "DE").glyph(style: .code), .symbol("wifi.slash"))
    }
    func testUnknownCountryIsQuestionmark() {
        XCTAssertEqual(makeState(.online, iso: nil).glyph(style: .emoji), .symbol("questionmark"))
        XCTAssertEqual(makeState(.online, iso: "XX_BAD").glyph(style: .image), .symbol("questionmark"))
    }
    func testStylesRender() {
        XCTAssertEqual(makeState(.online, iso: "DE").glyph(style: .emoji), .text("🇩🇪"))
        XCTAssertEqual(makeState(.online, iso: "de").glyph(style: .code), .text("DE"))
        XCTAssertEqual(makeState(.online, iso: "DE").glyph(style: .image), .flagImage(iso: "de"))
    }
    func testCheckingKeepsLastKnownExit() {
        // .checking renders like online — state carries the last known exit
        XCTAssertEqual(makeState(.checking, iso: "DE").glyph(style: .emoji), .text("🇩🇪"))
    }
    func testCodableRoundTrip() throws {
        let s = makeState(.online, iso: "DE")
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ExitState.self, from: data), s)
        let relay = ExitState(privateRelay: .active(egressIP: "5.6.7.8", egressCountry: "DE"), since: Date())
        let d2 = try JSONEncoder().encode(relay)
        XCTAssertEqual(try JSONDecoder().decode(ExitState.self, from: d2), relay)
    }
    func testCodableRoundTripWithIPv6Fields() throws {
        var s = makeState(.online, iso: "NL")
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "DE", org: "Deutsche Telekom", provider: "test", fetchedAt: Date())
        s.ipv6Leak = true
        s.route.v6DefaultInterface = "en0"
        s.route.v6IsVPN = false
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ExitState.self, from: data), s)
    }
    func testDecodesOldJSONWithoutIPv6Fields() throws {
        // Documented, additive API change: JSON produced by pre-IPv6-leak-detector versions
        // has no exit6/ipv6Leak/v6DefaultInterface/v6IsVPN keys at all. Must still decode
        // cleanly, defaulting the new fields to nil/false.
        let old = """
        {"connectivity":"online","exit":{"countryCode":"DE","ip":"1.2.3.4","provider":"test","fetchedAt":"2025-08-12T12:00:00Z"},
         "privateRelay":{"status":"inactive"},"route":{"isVPN":false,"hijackRoutePresent":false},
         "since":"2025-08-12T12:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExitState.self, from: old)
        XCTAssertNil(decoded.exit6)
        XCTAssertFalse(decoded.ipv6Leak)
        XCTAssertNil(decoded.route.v6DefaultInterface)
        XCTAssertFalse(decoded.route.v6IsVPN)
        XCTAssertEqual(decoded.exit?.countryCode, "DE")
    }
}
