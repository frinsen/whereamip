import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The help window's body: bundled Markdown, loaded through the same locator every
/// other UI resource uses (never `Bundle.module`), rendered by the same tiny
/// Markdown renderer the welcome window uses.
final class HelpContentTests: XCTestCase {
    let font = NSFont.systemFont(ofSize: 12)

    func testHelpMarkdownIsBundledAndIsRealCopy() {
        let help = HelpContent.markdown()
        XCTAssertFalse(help.isEmpty)
        XCTAssertNotEqual(help, HelpContent.fallback, "help.md did not resolve from the bundle")
        XCTAssertFalse(help.contains(".md"), "a file name leaked into the copy: \(help)")
    }

    func testHelpCoversTheThingsTheDropdownCannotExplainItself() {
        // Not wording assertions — presence assertions. Each of these is a question
        // the menu bar itself has no room to answer, which is why this window exists.
        let help = HelpContent.markdown()
        for topic in ["menu bar", "Since", "Checked", "Configured resolvers",
                      "⌘C", "⌥⌘C", "⇧⌘C", "⌘R", "⌘Q",
                      "whereamip status", "whereamip watch", "whereamip diagnostics",
                      "whereamip debug", "github.com/frinsen/whereamip"] {
            XCTAssertTrue(help.contains(topic), "help.md never mentions \(topic)")
        }
    }

    func testHelpRendersWithoutLeavingMarkupBehind() {
        let rendered = WelcomeContent.rendered(HelpContent.markdown(), font: font, alignment: .left).string
        XCTAssertFalse(rendered.isEmpty)
        XCTAssertFalse(rendered.contains("**"), "unrendered bold markup: \(rendered)")
        XCTAssertFalse(rendered.contains("\n- "), "unrendered bullet markup: \(rendered)")
    }

    // MARK: - never a crash, never a raw path or key on screen

    func testMissingFileFallsBackToASentenceRatherThanAPathOrAnEmptyWindow() {
        let empty = try! emptyBundle()
        let text = HelpContent.markdown(in: empty)
        XCTAssertEqual(text, HelpContent.fallback)
        // A true sentence, not a file path and not a lookup key. (The URL it points
        // at is copy, which is why this checks for path/bundle debris specifically.)
        for debris in [".md", ".bundle", "/Users", "help/help", "help.window"] {
            XCTAssertFalse(text.contains(debris), "\(debris) must never reach the window: \(text)")
        }
        XCTAssertTrue(text.hasSuffix("."), "the fallback is a sentence: \(text)")
    }

    func testEmptyFileIsTreatedAsMissing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("HelpContentTests-\(UUID().uuidString)")
        let bundleURL = root.appendingPathComponent("resources.bundle/help")
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "   \n\n".write(to: bundleURL.appendingPathComponent("help.md"),
                            atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(url: root.appendingPathComponent("resources.bundle")))
        XCTAssertEqual(HelpContent.markdown(in: bundle), HelpContent.fallback)
    }

    private func emptyBundle() throws -> Bundle {
        let fm = FileManager.default
        let empty = fm.temporaryDirectory.appendingPathComponent("HelpContentTests-empty-\(UUID().uuidString)")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        return try XCTUnwrap(Bundle(url: empty))
    }
}
