import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The in-app language override, end to end through the two text pipelines it controls.
///
/// Pinning `L10n.languageSetting` is what makes these deterministic: every assertion below
/// holds identically on an English Mac and on the maintainer's German one, which the earlier
/// locale tests could only approximate by pinning each call site.
final class LanguageOverrideTests: XCTestCase {
    override func tearDown() {
        L10n.languageSetting = { Settings().language }   // never leak an override into other tests
        super.tearDown()
    }

    // MARK: - strings

    func testOverridingToEnglishGivesEnglishStringsWhateverTheSystemSays() {
        L10n.languageSetting = { "en" }
        XCTAssertEqual(L10n.string(.menuRefresh), "Refresh")
        XCTAssertEqual(L10n.string(.menuQuit), "Quit WhereAmIP")
    }

    func testOverridingToGermanGivesGermanStrings() {
        L10n.languageSetting = { "de" }
        XCTAssertEqual(L10n.string(.menuRefresh), "Aktualisieren")
        XCTAssertEqual(L10n.string(.menuQuit), "WhereAmIP beenden")
    }

    func testFormattedLookupsFollowTheOverrideToo() {
        L10n.languageSetting = { "de" }
        XCTAssertEqual(L10n.string(.menuSince, "17.08.26"), "Seit 17.08.26")
        XCTAssertEqual(L10n.string(.dnsRowMore, 3), "  (+3 weitere)")
    }

    func testSwitchingBackAndForthTakesEffectImmediately() {
        // The point of the whole feature: no relaunch, no cached table to invalidate.
        for _ in 0..<3 {
            L10n.languageSetting = { "de" }
            XCTAssertEqual(L10n.string(.menuSettings), "Einstellungen")
            L10n.languageSetting = { "en" }
            XCTAssertEqual(L10n.string(.menuSettings), "Settings")
        }
    }

    func testSystemDefaultLeavesResolutionToFoundation() {
        // Whatever the host prefers, it must be a real translation and never a raw key.
        L10n.languageSetting = { AppLanguage.system }
        let refresh = L10n.string(.menuRefresh)
        XCTAssertTrue(["Refresh", "Aktualisieren"].contains(refresh), "got: \(refresh)")
        XCTAssertNotEqual(refresh, L10nKey.menuRefresh.rawValue)
    }

    func testAnUnsupportedStoredValueFallsBackRatherThanShowingKeys() {
        L10n.languageSetting = { "fr" }
        let refresh = L10n.string(.menuRefresh)
        XCTAssertTrue(["Refresh", "Aktualisieren"].contains(refresh), "got: \(refresh)")
    }

    // MARK: - bundled markdown follows the same setting

    func testMarkdownFollowsTheOverride() {
        L10n.languageSetting = { "de" }
        XCTAssertTrue(WelcomeContent.markdown(milestone: nil).contains("Menüleiste"))
        XCTAssertTrue(HelpContent.markdown().contains("Tastaturkürzel"))

        L10n.languageSetting = { "en" }
        XCTAssertTrue(WelcomeContent.markdown(milestone: nil).contains("menu bar"))
        XCTAssertTrue(HelpContent.markdown().contains("Keyboard shortcuts"))
    }

    func testWelcomeCopyHeadingAndBodySpeakTheSameLanguage() {
        L10n.languageSetting = { "de" }
        let copy = WelcomeContent.copy(for: "")
        XCTAssertTrue(copy.heading.hasPrefix("Willkommen bei"), "got: \(copy.heading)")
        XCTAssertTrue(copy.markdown.contains("Menüleiste"))
    }

    /// The milestone decision is a version comparison, not a text one — it must not shift
    /// when the language does.
    func testWhichMilestoneIsShownIsLanguageIndependent() {
        L10n.languageSetting = { "de" }
        let german = WelcomeContent.copy(for: "0.1")
        L10n.languageSetting = { "en" }
        let english = WelcomeContent.copy(for: "0.1")
        XCTAssertTrue(german.heading.contains(welcomeMilestone))
        XCTAssertTrue(english.heading.contains(welcomeMilestone))
        XCTAssertNotEqual(german.markdown, english.markdown, "same milestone, different language")
        XCTAssertEqual(shouldShowWelcome(stored: "0.1"), shouldShowWelcome(stored: "0.1"))
    }

    // MARK: - the whole menu, and notifications

    func testTheDropdownRendersInTheOverriddenLanguage() {
        let state = ExitState(connectivity: .online,
                              exit: ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Berlin",
                                             org: "Vodafone", provider: "ipwho.is", fetchedAt: Date()),
                              route: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "WARP"),
                              since: Date())
        L10n.languageSetting = { "de" }
        let german = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                       launchAtLogin: false, actions: MenuActions())
            .items.map(\.title)
        XCTAssertTrue(german.contains("Aktualisieren"), "got: \(german)")
        XCTAssertTrue(german.contains("WhereAmIP beenden"))
        XCTAssertTrue(german.contains { $0.hasPrefix("Seit ") })

        L10n.languageSetting = { "en" }
        let english = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                        launchAtLogin: false, actions: MenuActions())
            .items.map(\.title)
        XCTAssertTrue(english.contains("Refresh"), "got: \(english)")
        XCTAssertTrue(english.contains("Quit WhereAmIP"))
    }

    /// Notifications go through L10n like everything else, so they follow for free — but
    /// "for free" is worth one assertion, since they are built on a different code path.
    func testNotificationTextFollowsTheOverride() {
        L10n.languageSetting = { "de" }
        let (title, body) = NotificationText.text(for: .connectivityLost(hijackSuspected: false))!
        XCTAssertEqual(title, "Internet nicht erreichbar")
        XCTAssertEqual(body, "Netzwerk aktiv, Prüfungen schlagen fehl")

        L10n.languageSetting = { "en" }
        let (englishTitle, _) = NotificationText.text(for: .connectivityLost(hijackSuspected: false))!
        XCTAssertEqual(englishTitle, "Internet unreachable")
    }
}
