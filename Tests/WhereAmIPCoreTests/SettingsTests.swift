import XCTest
@testable import WhereAmIPCore

final class SettingsTests: XCTestCase {
    var settings: Settings!
    override func setUp() {
        let d = UserDefaults(suiteName: "test.whereamip")!
        d.removePersistentDomain(forName: "test.whereamip")
        settings = Settings(defaults: d)
    }
    func testDefaults() {
        XCTAssertEqual(settings.menuBarStyle, .emoji)
        XCTAssertFalse(settings.notificationsEnabled)
    }
    func testPersistence() {
        settings.menuBarStyle = .code
        XCTAssertEqual(settings.menuBarStyle, .code)
    }
    func testConfigSurface() throws {
        try settings.set(key: "style", value: "image")
        XCTAssertEqual(settings.menuBarStyle, .image)
        try settings.set(key: "notify", value: "true")
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertThrowsError(try settings.set(key: "style", value: "banana"))
        XCTAssertThrowsError(try settings.set(key: "nope", value: "x"))
        XCTAssertEqual(settings.allValues().map(\.key), ["notify", "style"])
    }
}
