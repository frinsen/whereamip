import XCTest
@testable import WhereAmIPUI

/// Guards the *mechanism* the rest of the UI tests now rely on: if the strings
/// bundle silently stopped resolving, every lookup would return its own key and
/// every lookup-based assertion in MenuBuilderTests/NotificationTextTests would
/// still pass (key == key). These tests are the ones that would fail instead.
final class L10nTests: XCTestCase {

    // MARK: - the en bundle actually resolves

    func testEnglishBundleResolvesRealCopyNotTheKey() {
        // Deliberately literal — the one place wording IS pinned, so a broken
        // bundle path can't pass the suite by returning keys everywhere.
        XCTAssertEqual(L10n.string(.menuRefresh), "Refresh")
        XCTAssertNotEqual(L10n.string(.menuRefresh), L10nKey.menuRefresh.rawValue)
        XCTAssertEqual(L10n.string(.menuQuit), "Quit WhereAmIP")
        XCTAssertEqual(L10n.string(.welcomeDone), "Done")
    }

    func testFormattedLookupFillsPlaceholdersInOrder() {
        XCTAssertEqual(L10n.string(.menuHeader, "9.9.9"), "WhereAmIP v9.9.9")
        XCTAssertEqual(L10n.string(.menuUpdateRestart, "0.5"), "↻ Restart to finish update (v0.5)")
        XCTAssertEqual(L10n.string(.menuRouteLink, "Wi-Fi", "en0"), "Route: Wi-Fi (en0)")
        XCTAssertEqual(L10n.string(.dnsRowMore, 3), "  (+3 more)")
    }

    // MARK: - completeness

    func testEveryDeclaredKeyExistsInTheStringsFile() {
        // CaseIterable is the whole reason keys are a typed enum: adding a case
        // without adding the line to Localizable.strings fails right here, and no
        // hand-maintained list can drift out of sync with the call sites.
        for key in L10nKey.allCases {
            let value = L10n.string(key)
            XCTAssertNotEqual(value, key.rawValue, "missing from en.lproj/Localizable.strings: \(key.rawValue)")
            XCTAssertFalse(value.isEmpty, "empty value for \(key.rawValue)")
        }
    }

    func testKeysAreLowercaseDotSeparatedAndUnderAKnownPrefix() {
        let prefixes = ["menu.", "settings.", "dns.", "notification.", "welcome."]
        for key in L10nKey.allCases {
            XCTAssertTrue(prefixes.contains { key.rawValue.hasPrefix($0) },
                          "unrecognised key namespace: \(key.rawValue)")
            XCTAssertFalse(key.rawValue.contains(" "), "keys never contain spaces: \(key.rawValue)")
        }
    }

    // MARK: - bundle resolution from a real .app layout

    /// make-app-bundle.sh copies the SwiftPM resource bundle into
    /// `WhereAmIP.app/Contents/Resources/`. Nothing in `swift test` exercises that
    /// path (tests resolve from `.build/debug/`), so this rebuilds that layout in a
    /// temp directory and proves the FIRST candidate — `Bundle.main.resourceURL` —
    /// finds it, strings included. A regression here means a shipped .app shows
    /// raw keys while the whole suite stays green.
    func testResolvesBundleFromAppContentsResourcesLayout() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("L10nTests-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("WhereAmIP.app/Contents")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "".write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try fm.copyItem(at: uiResourceBundle.bundleURL,
                        to: resources.appendingPathComponent("whereamip_WhereAmIPUI.bundle"))

        // A token that resolves nothing, so a hit can only have come from `main`
        // — otherwise the test's own .build/debug/ layout would satisfy it and
        // prove nothing about the .app case.
        let emptyDir = root.appendingPathComponent("empty")
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let main = try XCTUnwrap(Bundle(url: root.appendingPathComponent("WhereAmIP.app")))
        let token = try XCTUnwrap(Bundle(url: emptyDir))

        let resolved = try XCTUnwrap(ResourceBundleLocator.resolve(
            named: "whereamip_WhereAmIPUI.bundle", main: main, token: token))
        XCTAssertTrue(resolved.bundleURL.path.contains("WhereAmIP.app/Contents/Resources"),
                      "resolved the wrong candidate: \(resolved.bundleURL.path)")
        XCTAssertEqual(resolved.localizedString(forKey: "menu.refresh", value: nil, table: nil), "Refresh")
        XCTAssertNotNil(resolved.url(forResource: "welcome/intro", withExtension: "md"))
        XCTAssertNotNil(resolved.url(forResource: "flags/de", withExtension: "png"))
    }

    func testResolutionReturnsNilRatherThanCrashingWhenNothingIsFound() {
        let fm = FileManager.default
        let empty = fm.temporaryDirectory.appendingPathComponent("L10nTests-empty-\(UUID().uuidString)")
        try? fm.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: empty) }
        let nowhere = Bundle(url: empty)!
        XCTAssertNil(ResourceBundleLocator.resolve(named: "does-not-exist.bundle", main: nowhere, token: nowhere))
    }
}
