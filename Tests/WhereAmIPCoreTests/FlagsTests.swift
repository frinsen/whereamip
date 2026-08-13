import XCTest
@testable import WhereAmIPCore

final class FlagsTests: XCTestCase {
    func testKnownCodes() {
        XCTAssertEqual(Flags.emoji(countryCode: "DE"), "🇩🇪")
        XCTAssertEqual(Flags.emoji(countryCode: "nl"), "🇳🇱")
    }
    func testInvalidCodes() {
        XCTAssertNil(Flags.emoji(countryCode: ""))
        XCTAssertNil(Flags.emoji(countryCode: "D"))
        XCTAssertNil(Flags.emoji(countryCode: "DEU"))
        XCTAssertNil(Flags.emoji(countryCode: "D1"))
    }
}
