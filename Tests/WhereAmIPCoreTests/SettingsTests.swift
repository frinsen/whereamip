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
        XCTAssertTrue(settings.updatesEnabled)
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
        XCTAssertEqual(settings.allValues().map(\.key), ["notify", "style", "updates", "dns"])
    }
    func testUpdatesConfigSurface() throws {
        try settings.set(key: "updates", value: "false")
        XCTAssertFalse(settings.updatesEnabled)
        try settings.set(key: "updates", value: "true")
        XCTAssertTrue(settings.updatesEnabled)
        XCTAssertThrowsError(try settings.set(key: "updates", value: "banana"))
        XCTAssertTrue(settings.allValues().map(\.key).contains("updates"))
    }
    func testDNSProbeEnabledDefaultsTrue() {
        XCTAssertTrue(settings.dnsProbeEnabled)
    }
    func testDNSProbeEnabledPersistsFalse() {
        settings.dnsProbeEnabled = false
        XCTAssertFalse(settings.dnsProbeEnabled)
    }
    func testSetKeyDNS() throws {
        try settings.set(key: "dns", value: "false")
        XCTAssertFalse(settings.dnsProbeEnabled)
        XCTAssertThrowsError(try settings.set(key: "dns", value: "maybe"))
    }
    func testAllValuesIncludesDNS() {
        XCTAssertTrue(settings.allValues().contains { $0.key == "dns" })
    }
}
