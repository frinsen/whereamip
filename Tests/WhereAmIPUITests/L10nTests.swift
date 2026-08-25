import XCTest
@testable import WhereAmIPUI

/// Guards the *mechanism* the rest of the UI tests now rely on: if the strings
/// bundle silently stopped resolving, every lookup would return its own key and
/// every lookup-based assertion in MenuBuilderTests/NotificationTextTests would
/// still pass (key == key). These tests are the ones that would fail instead.
final class L10nTests: XCTestCase {

    // The literal assertions below pin ENGLISH values, so the language override
    // must be pinned too: without this, a host Mac whose real app settings carry
    // an explicit language choice (Settings ▸ Language ▸ Deutsch) leaks that
    // choice into the suite — found in the field the first time the maintainer
    // ended a picker test on Deutsch and five assertions went red. Same rule as
    // pinning the system locale, one seam further up.
    private var savedLanguageSetting: (() -> String)!
    override func setUp() {
        super.setUp()
        savedLanguageSetting = L10n.languageSetting
        L10n.languageSetting = { "en" }
    }
    override func tearDown() {
        L10n.languageSetting = savedLanguageSetting
        super.tearDown()
    }

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

    // MARK: - completeness, per locale

    /// Every localization this app ships. Parameterizing the completeness check over this
    /// list (rather than copying the test per language) is what keeps adding a locale a
    /// matter of adding a folder and one entry here.
    static let shippedLocales = ["en", "de"]

    /// The `.lproj` bundle for `locale`, resolved out of the located UI bundle. Deliberately
    /// NOT `L10n.string`, which answers in whatever language the test HOST prefers — these
    /// assertions have to hold on every machine, including an English one checking German.
    func bundle(for locale: String) throws -> Bundle {
        let path = try XCTUnwrap(uiResourceBundle.path(forResource: locale, ofType: "lproj"),
                                 "\(locale).lproj is missing from the resource bundle")
        return try XCTUnwrap(Bundle(path: path))
    }
    func value(_ key: L10nKey, in bundle: Bundle) -> String {
        bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
    }

    func testEveryDeclaredKeyExistsInEveryShippedLocale() throws {
        // CaseIterable is the whole reason keys are a typed enum: adding a case without
        // adding the line fails right here — now for each locale, so a translation can't
        // silently lag behind the English file.
        for locale in Self.shippedLocales {
            let bundle = try self.bundle(for: locale)
            for key in L10nKey.allCases {
                let value = self.value(key, in: bundle)
                XCTAssertNotEqual(value, key.rawValue,
                                  "missing from \(locale).lproj/Localizable.strings: \(key.rawValue)")
                XCTAssertFalse(value.isEmpty, "empty value for \(key.rawValue) in \(locale)")
            }
        }
    }

    /// A translation that drops or reorders a placeholder is a CRASH — `String(format:)`
    /// reads an argument that was never passed — and it is a crash only speakers of that
    /// language would ever hit. Cheap to prevent, so it is prevented mechanically.
    func testPlaceholdersMatchTheBaseLocaleExactly() throws {
        let base = try bundle(for: "en")
        for locale in Self.shippedLocales where locale != "en" {
            let translated = try bundle(for: locale)
            for key in L10nKey.allCases {
                XCTAssertEqual(Self.placeholders(in: value(key, in: translated)),
                               Self.placeholders(in: value(key, in: base)),
                               "placeholder mismatch for \(key.rawValue) in \(locale)")
            }
        }
    }

    /// The format specifiers in order, e.g. ["%@", "%@", "%d"]. `%%` is a literal percent
    /// and is deliberately not counted.
    static func placeholders(in value: String) -> [String] {
        var found: [String] = []
        var rest = Substring(value)
        while let percent = rest.firstIndex(of: "%") {
            let after = rest.index(after: percent)
            guard after < rest.endIndex else { break }
            let specifier = rest[after]
            if specifier != "%" { found.append("%\(specifier)") }
            rest = rest[rest.index(after: after)...]
        }
        return found
    }

    /// Foundation, not us, decides which `.lproj` a German Mac reads — so this pins the two
    /// things that decision depends on: that the shipped bundle actually ADVERTISES both
    /// localizations, and that Foundation's own matcher picks German for a German
    /// preference (region variants included). `preferredLocalizations(from:forPreferences:)`
    /// is the very rule `localizedString` applies, run here against the real bundle.
    func testTheBundleAdvertisesEveryShippedLocaleAndFoundationPicksTheRightOne() {
        let available = uiResourceBundle.localizations
        for locale in Self.shippedLocales {
            XCTAssertTrue(available.contains(locale), "\(locale) missing from \(available)")
        }
        for preference in [["de-DE", "en-US"], ["de"], ["de-AT", "fr"]] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: preference).first,
                           "de", "German preference \(preference) did not select de.lproj")
        }
        for preference in [["en-GB", "de-DE"], ["fr-FR"], ["en"]] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: available, forPreferences: preference).first,
                           "en", "\(preference) should fall to the development language")
        }
    }

    /// One heading, both variants, every locale: the category the heading used to spell
    /// out ("Welcome to …", "— what's new", "— Neuerungen") now lives in the badge above
    /// it, and having it in BOTH places is exactly the duplication this change removed.
    /// The German heading is the pointed case — its old "— Neuerungen" was the wording
    /// inconsistency that got flagged, since the menu entry opening that window says
    /// "Neue Funktionen".
    func testTheHeadingIsJustTheVersionedNameInEveryLocale() throws {
        for locale in Self.shippedLocales {
            let heading = value(.welcomeHeading, in: try bundle(for: locale))
            XCTAssertEqual(heading, "WhereAmIP v%@", "\(locale) heading carries more than the name")
            for category in ["Welcome", "Willkommen", "what's new", "Neuerungen", "Neue Funktionen"] {
                XCTAssertFalse(heading.localizedCaseInsensitiveContains(category),
                               "\(locale) heading still spells out the category, which the badge now carries: \(heading)")
            }
        }
    }

    /// The welcome window's notify caption is a SINGLE-LINE label in a fixed 353pt slot
    /// (see WelcomeWindow) — it truncates rather than wraps. German runs longer than
    /// English almost by default, so this is measured, not eyeballed, for every locale.
    func testNotifyCaptionFitsItsSingleLineSlotInEveryLocale() throws {
        let available: CGFloat = 372 - 19   // window content width minus the checkbox indent
        for locale in Self.shippedLocales {
            let caption = value(.welcomeNotifyCaption, in: try bundle(for: locale))
            let width = (caption as NSString)
                .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
            XCTAssertLessThanOrEqual(width, available,
                                     "\(locale) notify caption is \(Int(width))pt, truncates at \(Int(available))pt: \(caption)")
        }
    }

    /// The update row is the FIRST row of the dropdown and the widest thing in it — wide
    /// enough that spelling the command out in it was rejected for costing ~100pt (see the
    /// comment above `menu.update.available`). The direct-install variant is a second
    /// wording for the same row, so the accepted one is its budget: measured per locale in
    /// the menu font, not eyeballed. At the time of writing, en 322pt vs 334pt and
    /// de 319pt vs 324pt.
    func testDownloadPageRowIsNoWiderThanTheCopyCommandRowInEveryLocale() throws {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ key: L10nKey, _ bundle: Bundle) -> CGFloat {
            let label = String(format: value(key, in: bundle), "0.5.1")
            return (label as NSString).size(withAttributes: [.font: font]).width
        }
        for locale in Self.shippedLocales {
            let bundle = try self.bundle(for: locale)
            let budget = width(.menuUpdateAvailable, bundle)
            let download = width(.menuUpdateAvailableDownload, bundle)
            XCTAssertLessThanOrEqual(download, budget,
                                     "\(locale) download-page row is \(Int(download))pt, "
                                     + "wider than the \(Int(budget))pt row it replaces: "
                                     + value(.menuUpdateAvailableDownload, in: bundle))
        }
    }

    func testKeysAreLowercaseDotSeparatedAndUnderAKnownPrefix() {
        let prefixes = ["menu.", "settings.", "dns.", "notification.", "welcome.", "help."]
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
