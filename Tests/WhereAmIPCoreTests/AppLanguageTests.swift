import XCTest
@testable import WhereAmIPCore

/// The in-app language override: which language list every text lookup should consult.
///
/// Pure resolution, no bundles and no AppKit — the UI layer feeds the result of this into
/// its strings table and its Markdown loader, so getting the list right here is what makes
/// the whole pipeline switchable at runtime.
final class AppLanguageTests: XCTestCase {
    let system = ["fr-FR", "en-US"]

    func testSystemDefaultDefersToTheOSPreferenceUntouched() {
        XCTAssertEqual(AppLanguage.effectiveLanguages(override: AppLanguage.system,
                                                      systemPreference: system), system)
    }

    func testAnOverrideReplacesTheWholePreferenceList() {
        // Not prepended: an explicit choice must not silently fall through to the next
        // system language for a file that happens to be untranslated — the per-file English
        // fallback already covers that, and it is the honest one.
        XCTAssertEqual(AppLanguage.effectiveLanguages(override: "de", systemPreference: system), ["de"])
        XCTAssertEqual(AppLanguage.effectiveLanguages(override: "en", systemPreference: system), ["en"])
    }

    func testUnsupportedOrGarbageValuesFallBackToTheSystemPreference() {
        // A value that got into defaults some other way (hand-edited plist, a future
        // version's language) must never blank the UI — it degrades to system behaviour.
        for junk in ["fr", "", "sytem", "DE!", "en-US"] {
            XCTAssertEqual(AppLanguage.effectiveLanguages(override: junk, systemPreference: system),
                           system, "'\(junk)' should have fallen back to the system preference")
        }
    }

    func testOverrideCodeIsNilForSystemAndForAnythingUnsupported() {
        XCTAssertNil(AppLanguage.overrideCode(AppLanguage.system))
        XCTAssertNil(AppLanguage.overrideCode("fr"))
        XCTAssertEqual(AppLanguage.overrideCode("de"), "de")
        XCTAssertEqual(AppLanguage.overrideCode("en"), "en")
    }

    func testSupportedListMatchesWhatTheAppActuallyShips() {
        // The .lproj folders are the source of truth; this is the CLI/menu-facing copy of
        // that list, and L10nTests asserts the same set from the bundle side.
        XCTAssertEqual(AppLanguage.supported, ["en", "de"])
        XCTAssertFalse(AppLanguage.supported.contains(AppLanguage.system))
    }
}
