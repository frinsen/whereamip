import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The help window's GitHub pointer has to be a real link, not link-shaped text.
///
/// Two halves, and only one of them is testable here: the attributed string must carry a
/// `.link` attribute with the right URL (asserted below), and the VIEW must be one that
/// acts on it — an NSTextField never will, which is why the help body is an NSTextView.
/// The click itself is a manual check.
final class HelpLinkTests: XCTestCase {
    let font = NSFont.systemFont(ofSize: 12)

    func linkAttributes(in rendered: NSAttributedString) -> [(URL, NSRange)] {
        var found: [(URL, NSRange)] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
            if let url = value as? URL { found.append((url, range)) }
            if let string = value as? String, let url = URL(string: string) { found.append((url, range)) }
        }
        return found
    }

    func testMarkdownLinkSyntaxBecomesARealLinkAttribute() throws {
        let rendered = WelcomeContent.rendered("See [the repo](https://github.com/frinsen/whereamip) for more",
                                               font: font, alignment: .left)
        let links = linkAttributes(in: rendered)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(try XCTUnwrap(links.first).0.absoluteString, "https://github.com/frinsen/whereamip")
        // The label text is what shows; the URL is not spelled out twice.
        XCTAssertEqual(rendered.string, "See the repo for more")
    }

    func testTheLinkIsVisuallyDistinctFromBodyText() throws {
        let rendered = WelcomeContent.rendered("[the repo](https://github.com/frinsen/whereamip) and text",
                                               font: font, alignment: .left)
        let range = try XCTUnwrap(linkAttributes(in: rendered).first).1
        // Explicit, because rendered() paints the whole string with the body colour — a link
        // left in that colour reads as ordinary text no matter how clickable it is.
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                       .linkColor)
        XCTAssertNotNil(rendered.attribute(.underlineStyle, at: range.location, effectiveRange: nil))
        // Body text keeps the normal colour.
        let plainIndex = rendered.length - 1
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: plainIndex, effectiveRange: nil) as? NSColor,
                       .labelColor)
    }

    func testBundledHelpCarriesTheGitHubLinkInEveryLocale() throws {
        for languages in [["en"], ["de"]] {
            let markdown = HelpContent.markdown(preferredLanguages: languages)
            let rendered = WelcomeContent.rendered(markdown, font: font, alignment: .left)
            let links = linkAttributes(in: rendered)
            XCTAssertEqual(links.count, 1, "expected exactly one link in \(languages) help")
            XCTAssertEqual(try XCTUnwrap(links.first).0.absoluteString,
                           "https://github.com/frinsen/whereamip", "\(languages)")
            // The raw markdown syntax must not survive into what the user reads.
            XCTAssertFalse(rendered.string.contains("]("), "unrendered link markup in \(languages)")
            XCTAssertFalse(rendered.string.contains("https://"),
                           "the URL should be the link target, not visible body text, in \(languages)")
        }
    }
}
