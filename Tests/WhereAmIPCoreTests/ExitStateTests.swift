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
}
