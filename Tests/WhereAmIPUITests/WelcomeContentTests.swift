import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

final class WelcomeContentTests: XCTestCase {
    let font = NSFont.systemFont(ofSize: 12)

    func plain(_ markdown: String) -> String {
        WelcomeContent.rendered(markdown, font: font).string
    }

    // MARK: - which copy, for which start

    func testFirstEverStartShowsTheWelcomeHeadingAndTheIntroPitch() {
        let copy = WelcomeContent.copy(for: "")
        XCTAssertEqual(copy.heading, L10n.string(.welcomeHeadingFirst, whereamipVersion))
        XCTAssertEqual(copy.markdown, WelcomeContent.markdown(milestone: nil))
    }

    func testMilestoneRetriggerIsTitledWithTheMilestoneNotTheRunningVersion() {
        // The whole point: this window re-opened because `welcomeMilestone`
        // advanced, and the running build may already be patch releases past it.
        let copy = WelcomeContent.copy(for: "0.1")
        XCTAssertEqual(copy.heading, L10n.string(.welcomeHeadingMilestone, welcomeMilestone))
        XCTAssertTrue(copy.heading.contains(welcomeMilestone))
    }

    func testMilestoneRetriggerShowsTheMilestoneHighlightsNotThePitch() {
        let copy = WelcomeContent.copy(for: "0.1")
        XCTAssertEqual(copy.markdown, WelcomeContent.markdown(milestone: welcomeMilestone))
        XCTAssertNotEqual(copy.markdown, WelcomeContent.markdown(milestone: nil),
                          "the re-show must not just repeat the first-run pitch")
    }

    // MARK: - bundled markdown

    func testIntroMarkdownIsBundledAndIsRealCopy() {
        let intro = WelcomeContent.markdown(milestone: nil)
        XCTAssertFalse(intro.isEmpty)
        XCTAssertNotEqual(intro, WelcomeContent.fallbackPitch, "intro.md did not resolve from the bundle")
        XCTAssertFalse(intro.contains("/"), "a path leaked into the body copy: \(intro)")
    }

    func testCurrentMilestoneShipsHighlights() {
        // Guards the release checklist: bumping welcomeMilestone without adding
        // its .md would silently re-show the first-run pitch to every upgrader.
        XCTAssertNotEqual(WelcomeContent.markdown(milestone: welcomeMilestone),
                          WelcomeContent.markdown(milestone: nil),
                          "Resources/welcome/\(welcomeMilestone).md is missing")
    }

    func testUnknownMilestoneFallsBackToTheIntroCopy() {
        XCTAssertEqual(WelcomeContent.markdown(milestone: "42.0"),
                       WelcomeContent.markdown(milestone: nil))
    }

    func testUnsafeMilestoneNameCannotEscapeTheWelcomeDirectory() {
        XCTAssertEqual(WelcomeContent.markdown(milestone: "../../Info"),
                       WelcomeContent.markdown(milestone: nil))
    }

    // MARK: - markdown rendering

    func testBulletsBecomeBulletGlyphsAndKeepOneItemPerLine() {
        let rendered = plain("- first\n- second\n")
        XCTAssertEqual(rendered, "• first\n• second")
    }

    func testHardWrappedSourceLinesJoinIntoOneParagraph() {
        XCTAssertEqual(plain("one two\nthree four\n"), "one two three four")
        XCTAssertEqual(plain("- one two\n  three four\n"), "• one two three four")
    }

    func testBlankLinesSeparateParagraphs() {
        XCTAssertEqual(plain("first\n\nsecond\n"), "first\nsecond")
    }

    func testInlineEmphasisIsRenderedAsFontsNotLeftAsMarkup() {
        let rendered = WelcomeContent.rendered("- **DNS** is watched", font: font)
        XCTAssertEqual(rendered.string, "• DNS is watched")
        XCTAssertFalse(rendered.string.contains("*"))
        let boldFont = rendered.attribute(.font, at: rendered.string.distance(
            from: rendered.string.startIndex,
            to: rendered.string.range(of: "DNS")!.lowerBound), effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: try XCTUnwrap(boldFont)).contains(.boldFontMask))
    }

    func testHeadingsLoseTheirHashes() {
        XCTAssertEqual(plain("## What's new\n"), "What's new")
    }

    func testEveryBundledFileRendersWithoutLeavingMarkupBehind() {
        for markdown in [WelcomeContent.markdown(milestone: nil),
                         WelcomeContent.markdown(milestone: welcomeMilestone)] {
            let rendered = plain(markdown)
            XCTAssertFalse(rendered.isEmpty)
            XCTAssertFalse(rendered.contains("**"), "unrendered bold markup: \(rendered)")
            XCTAssertFalse(rendered.contains("\n- "), "unrendered bullet markup: \(rendered)")
        }
    }

    func testBulletsAreLeftAlignedWhileParagraphsFollowTheRequestedAlignment() {
        // A centered list is unreadable; the first-run pitch stays centered.
        let bullet = WelcomeContent.rendered("- item", font: font, alignment: .center)
        let paragraph = WelcomeContent.rendered("plain", font: font, alignment: .center)
        XCTAssertEqual((bullet.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.alignment, .left)
        XCTAssertEqual((paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.alignment, .center)
    }

    func testColorIsSetExplicitlySoDarkModeIsNotBlackOnBlack() {
        let rendered = WelcomeContent.rendered("plain", font: font)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       .labelColor)
    }
}
