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
        XCTAssertEqual(settings.allValues().map(\.key),
                       ["notify", "style", "updates", "dns", "language", "applications"])
    }
    func testUpdatesConfigSurface() throws {
        try settings.set(key: "updates", value: "false")
        XCTAssertFalse(settings.updatesEnabled)
        try settings.set(key: "updates", value: "true")
        XCTAssertTrue(settings.updatesEnabled)
        XCTAssertThrowsError(try settings.set(key: "updates", value: "banana"))
        XCTAssertTrue(settings.allValues().map(\.key).contains("updates"))
    }

    // MARK: - dns (probe toggle)

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

    // MARK: - applications (live filesystem state, not stored in defaults)

    func testApplicationsAppearsInAllValuesReflectingLiveLinkState() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let linkPath = tmp.appendingPathComponent("WhereAmIP.app").path

        XCTAssertEqual(settings.allValues(applicationsLinkPath: linkPath)
            .first { $0.key == "applications" }?.value, "false")

        try ApplicationsLink.setLinked(true, bundlePath: "/opt/homebrew/Cellar/whereamip/0.3.2/libexec/WhereAmIP.app",
                                       linkPath: linkPath)
        XCTAssertEqual(settings.allValues(applicationsLinkPath: linkPath)
            .first { $0.key == "applications" }?.value, "true")
    }
    func testSetKeyApplicationsIsRejectedByGenericSetter() {
        // The generic setter has no bundle path to link against; the CLI
        // handles "applications" itself via ApplicationsLink directly.
        XCTAssertThrowsError(try settings.set(key: "applications", value: "true"))
    }

    // MARK: - welcome window milestone gating

    // MARK: - language override

    func testLanguageDefaultsToSystem() {
        XCTAssertEqual(settings.language, AppLanguage.system)
    }
    func testLanguageRoundTrips() throws {
        try settings.set(key: "language", value: "de")
        XCTAssertEqual(settings.language, "de")
        try settings.set(key: "language", value: "en")
        XCTAssertEqual(settings.language, "en")
        try settings.set(key: "language", value: "system")
        XCTAssertEqual(settings.language, AppLanguage.system)
    }
    func testLanguageRejectsAnythingItCannotActuallyShow() {
        // Same shape as the other typed keys: refuse at the boundary rather than storing a
        // value that would silently behave as "system" forever.
        for junk in ["fr", "banana", "EN", "de-DE", ""] {
            XCTAssertThrowsError(try settings.set(key: "language", value: junk), junk)
        }
        XCTAssertEqual(settings.language, AppLanguage.system, "a rejected value must not be stored")
    }
    func testLanguageAppearsInTheConfigSurface() throws {
        try settings.set(key: "language", value: "de")
        XCTAssertTrue(settings.allValues().contains { $0.key == "language" && $0.value == "de" })
    }
    /// A value that reached defaults some other way (older build, hand-edited plist) must
    /// read back as system rather than as itself — the reader is the last line of defence.
    func testUnsupportedStoredValueReadsBackAsSystem() {
        let defaults = UserDefaults(suiteName: "test.whereamip")!
        defaults.set("fr", forKey: "language")
        XCTAssertEqual(Settings(defaults: defaults).language, AppLanguage.system)
    }
    func testUnknownKeyErrorNamesLanguage() {
        // The error text is the CLI's discoverability surface for `config set`.
        do {
            try settings.set(key: "nope", value: "x")
            XCTFail("expected a throw")
        } catch let SettingsError.invalid(message) {
            XCTAssertTrue(message.contains("language"), "got: \(message)")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testWelcomedMilestoneDefaultsEmpty() {
        XCTAssertEqual(settings.welcomedMilestone, "")
    }
    func testWelcomedMilestonePersists() {
        settings.welcomedMilestone = welcomeMilestone
        XCTAssertEqual(settings.welcomedMilestone, welcomeMilestone)
    }
    func testWelcomedMilestoneNotExposedViaConfigKeys() {
        XCTAssertFalse(settings.allValues().map(\.key).contains("welcomedMilestone"))
        XCTAssertThrowsError(try settings.set(key: "welcomedMilestone", value: "0.4"))
    }

    // shouldShowWelcome(stored:) predicate table — kept relative to the
    // actual `welcomeMilestone` constant (not a hardcoded literal) so these
    // don't silently stop testing anything if the constant is ever bumped.
    func testShouldShowWelcomeStoredEmptyIsTrue() {
        XCTAssertTrue(shouldShowWelcome(stored: ""))
    }
    func testShouldShowWelcomeStoredEqualToMilestoneIsFalse() {
        XCTAssertFalse(shouldShowWelcome(stored: welcomeMilestone))
    }
    func testShouldShowWelcomeStoredOlderThanMilestoneIsTrue() {
        XCTAssertTrue(shouldShowWelcome(stored: "0.0.1"))
    }
    func testShouldShowWelcomeStoredNewerThanMilestoneIsFalse() {
        // Downgrade edge: stored is somehow ahead of the current constant.
        XCTAssertFalse(shouldShowWelcome(stored: "99.0"))
    }
}
