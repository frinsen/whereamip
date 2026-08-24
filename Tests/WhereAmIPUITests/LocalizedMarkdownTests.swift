import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// Language selection for the bundled Markdown.
///
/// The `.strings` tables are matched to the user's language by Foundation itself; these
/// folders are `.copy`'d resources, so this layer does that job by hand — and these tests
/// are what stand in for the framework guarantee the strings path gets for free.
final class LocalizedMarkdownTests: XCTestCase {

    // MARK: - the bundled copy, through the real loader

    func testGermanPreferredGetsGermanCopy() {
        let intro = WelcomeContent.markdown(milestone: nil, preferredLanguages: ["de-DE", "en-US"])
        XCTAssertTrue(intro.contains("Menüleiste"), "expected the German intro, got: \(intro)")
        let help = HelpContent.markdown(preferredLanguages: ["de"])
        XCTAssertTrue(help.contains("Tastaturkürzel"), "expected the German help")
    }

    func testEnglishPreferredGetsEnglishCopyEvenThoughAGermanFileExists() {
        let intro = WelcomeContent.markdown(milestone: nil, preferredLanguages: ["en-GB", "de-DE"])
        XCTAssertTrue(intro.contains("menu bar"), "expected the English intro, got: \(intro)")
        XCTAssertFalse(intro.contains("Menüleiste"))
    }

    func testRegionVariantsResolveToTheSameLanguage() {
        // de-AT and de_CH are German readers; one German file serves all of them.
        for variant in ["de-AT", "de_CH", "de"] {
            XCTAssertTrue(WelcomeContent.markdown(milestone: nil, preferredLanguages: [variant])
                .contains("Menüleiste"), "\(variant) did not resolve to German")
        }
    }

    func testAMissingTranslationFallsBackToEnglishPerFileNotPerLocale() {
        // 0.4 shipped before the German copy existed and has no de/0.4.md. A German reader
        // must still get those highlights in English rather than being dropped to the intro
        // pitch — the fallback is per FILE, so a translation can land one file at a time.
        let german = WelcomeContent.markdown(milestone: "0.4", preferredLanguages: ["de-DE"])
        let english = WelcomeContent.markdown(milestone: "0.4", preferredLanguages: ["en"])
        XCTAssertEqual(german, english)
        XCTAssertNotEqual(german, WelcomeContent.markdown(milestone: nil, preferredLanguages: ["de-DE"]),
                          "a missing translation must not silently become the intro pitch")
    }

    func testAnUnknownLanguageGetsTheBaseCopy() {
        XCTAssertEqual(WelcomeContent.markdown(milestone: nil, preferredLanguages: ["fr-FR", "it"]),
                       WelcomeContent.markdown(milestone: nil, preferredLanguages: ["en"]))
    }

    func testTheCurrentMilestoneIsTranslated() {
        // Guards the release checklist the same way the English one does: bumping
        // welcomeMilestone without a de/<milestone>.md would quietly serve German users
        // English highlights.
        XCTAssertNotEqual(WelcomeContent.markdown(milestone: welcomeMilestone, preferredLanguages: ["de"]),
                          WelcomeContent.markdown(milestone: welcomeMilestone, preferredLanguages: ["en"]),
                          "Resources/welcome/de/\(welcomeMilestone).md is missing")
    }

    func testWelcomeCopyPicksTheHeadingAndTheBodyInTheSameLanguage() {
        let copy = WelcomeContent.copy(for: "", preferredLanguages: ["de"])
        XCTAssertTrue(copy.markdown.contains("Menüleiste"))
    }

    // MARK: - the rules themselves, against a bundle built for the test

    /// A bundle with an English file and the requested translations, so selection can be
    /// asserted without depending on which files the app happens to ship today.
    func makeBundle(languages: [String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalizedMarkdownTests-\(UUID().uuidString)/res.bundle")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"),
                                                withIntermediateDirectories: true)
        try "base copy".write(to: root.appendingPathComponent("folder/doc.md"),
                              atomically: true, encoding: .utf8)
        for language in languages {
            let dir = root.appendingPathComponent("folder/\(language)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "\(language) copy".write(to: dir.appendingPathComponent("doc.md"),
                                         atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        return try XCTUnwrap(Bundle(url: root))
    }

    func testFirstMatchingPreferredLanguageWins() throws {
        let bundle = try makeBundle(languages: ["de", "fr"])
        XCTAssertEqual(LocalizedMarkdown.load(folder: "folder", name: "doc", bundle: bundle,
                                              preferredLanguages: ["fr", "de"]), "fr copy")
        XCTAssertEqual(LocalizedMarkdown.load(folder: "folder", name: "doc", bundle: bundle,
                                              preferredLanguages: ["de", "fr"]), "de copy")
    }

    func testAnUntranslatedHigherPreferenceDoesNotBlockALowerOne() throws {
        // Only German exists: an Italian-first reader whose second language is German gets
        // German, not English.
        let bundle = try makeBundle(languages: ["de"])
        XCTAssertEqual(LocalizedMarkdown.load(folder: "folder", name: "doc", bundle: bundle,
                                              preferredLanguages: ["it", "de", "en"]), "de copy")
    }

    func testEnglishInThePreferenceListStopsTheSearch() throws {
        let bundle = try makeBundle(languages: ["de"])
        XCTAssertEqual(LocalizedMarkdown.load(folder: "folder", name: "doc", bundle: bundle,
                                              preferredLanguages: ["en", "de"]), "base copy")
    }

    func testAnEmptyTranslationCountsAsMissing() throws {
        let bundle = try makeBundle(languages: ["de"])
        let deFile = bundle.bundleURL.appendingPathComponent("folder/de/doc.md")
        try "   \n\n".write(to: deFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(LocalizedMarkdown.load(folder: "folder", name: "doc", bundle: bundle,
                                              preferredLanguages: ["de"]), "base copy",
                       "a half-finished translation must not open a blank window")
    }

    func testNothingAtAllReturnsNil() throws {
        let bundle = try makeBundle(languages: [])
        XCTAssertNil(LocalizedMarkdown.load(folder: "folder", name: "missing", bundle: bundle,
                                            preferredLanguages: ["de", "en"]))
    }
}
