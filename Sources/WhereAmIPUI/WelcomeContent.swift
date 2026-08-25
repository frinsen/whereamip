import AppKit
import WhereAmIPCore

/// The welcome window's prose: which heading it shows, and the Markdown body that
/// goes under it.
///
/// Body copy is bundled Markdown (`Resources/welcome/*.md`) rather than strings,
/// because it is per-release prose with structure — the first-run pitch in
/// `intro.md`, and one `<milestone>.md` per release that earns a re-show. Adding a
/// milestone's highlights is therefore a new file plus a `welcomeMilestone` bump,
/// with no Swift involved.
///
/// Lives in WhereAmIPUI, not in the App target, for one blunt reason: the App
/// target is an executable with no test target, and this decision (first-run pitch
/// vs. which release's highlights, and the fallback when a file is missing) is
/// exactly the part that must not regress silently.
public enum WelcomeContent {
    /// Heading + body markdown for a given stored `welcomedMilestone`.
    public struct Copy: Equatable {
        public let heading: String
        public let markdown: String
    }

    /// Last resort when the resource bundle itself can't be found — the same
    /// never-crash convention as the flag assets falling back to emoji. It is the
    /// only user-facing sentence still living in Swift, and it exists so a broken
    /// bundle shows a true (if terse) window rather than a blank one or a raw path.
    static let fallbackPitch =
        "WhereAmIP shows the country flag of your real internet exit in the menu bar."

    /// Which of the two things this window can be. Both are reachable by name from
    /// Settings (Show Welcome Window / What's New); the launch-time auto-show still
    /// derives one from history, via `variant(for:)`.
    public enum Variant: Equatable, CaseIterable {
        /// The first-run pitch — what the app is — headed with the RUNNING version.
        case intro
        /// The current milestone's highlights, headed with the MILESTONE version.
        case whatsNew
    }

    /// Heading + body markdown for an explicitly chosen variant. No history is
    /// consulted: a reader who asks for the pitch gets the pitch, and one who asks
    /// what's new gets the highlights, however many times either has been seen.
    ///
    /// The what's-new heading is titled with the MILESTONE version, not the running
    /// one: these are the highlights of the release that earned a re-show, and the
    /// running build may already be several patch releases past it. A milestone with
    /// no bundled highlights falls back to the intro copy rather than showing an
    /// empty window (or, worse, a file path).
    public static func copy(variant: Variant,
                            preferredLanguages: [String] = L10n.effectiveLanguages()) -> Copy {
        switch variant {
        case .intro:
            return Copy(heading: L10n.string(.welcomeHeadingFirst, whereamipVersion),
                        markdown: markdown(milestone: nil, preferredLanguages: preferredLanguages))
        case .whatsNew:
            return Copy(heading: L10n.string(.welcomeHeadingMilestone, welcomeMilestone),
                        markdown: markdown(milestone: welcomeMilestone,
                                           preferredLanguages: preferredLanguages))
        }
    }

    /// What the LAUNCH-TIME auto-show opens, given what has been acknowledged: a first
    /// run (nothing acknowledged yet) gets the pitch, a milestone re-trigger gets the
    /// highlights. The only history-driven choice left — the two Settings entries name
    /// their variant outright.
    public static func variant(for storedMilestone: String) -> Variant {
        storedMilestone.isEmpty ? .intro : .whatsNew
    }

    /// What clicking Done stores as seen. Deliberately variant-blind: acknowledging is
    /// about the release, not about which of its two windows happened to be on screen,
    /// so reading What's New marks the milestone seen exactly as the auto-shown window
    /// does — and re-reading the pitch from Settings never un-sees it. Lives here rather
    /// than inline in the window because the App target has no test target, and this is
    /// the rule that decides whether an upgrade nags twice.
    public static func acknowledgedMilestone(for variant: Variant) -> String {
        welcomeMilestone
    }

    /// The auto-show path's copy in one step. Thin wrapper: `variant(for:)` decides,
    /// `copy(variant:)` renders.
    public static func copy(for storedMilestone: String,
                            preferredLanguages: [String] = L10n.effectiveLanguages()) -> Copy {
        copy(variant: variant(for: storedMilestone), preferredLanguages: preferredLanguages)
    }

    /// Bundled Markdown for `milestone`, or the intro pitch (nil milestone, missing
    /// file, empty file).
    /// `preferredLanguages` is injected only so the tests can pin the language rules; the
    /// app always passes the real preference. A milestone with no translation still shows
    /// its English highlights rather than silently dropping to the intro pitch — see
    /// LocalizedMarkdown for why per-file fallback beats per-locale all-or-nothing.
    public static func markdown(milestone: String?,
                                preferredLanguages: [String] = L10n.effectiveLanguages()) -> String {
        if let milestone, isSafeFileStem(milestone),
           let text = load(milestone, preferredLanguages: preferredLanguages) { return text }
        return load("intro", preferredLanguages: preferredLanguages) ?? fallbackPitch
    }

    private static func load(_ name: String, preferredLanguages: [String]) -> String? {
        LocalizedMarkdown.load(folder: "welcome", name: name, bundle: uiResourceBundle,
                               preferredLanguages: preferredLanguages)
    }

    /// `welcomeMilestone` is a maintainer-set constant, not user input — this is
    /// belt-and-suspenders so a typo can never turn into a path that escapes the
    /// bundle's welcome/ directory.
    private static func isSafeFileStem(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
            && !name.contains("..")
    }

    // MARK: - rendering

    private struct Block {
        var text: String
        var isBullet: Bool
    }

    /// Renders the small Markdown subset the welcome copy uses — paragraphs,
    /// `- ` bullets, and inline `**bold**`/`*italic*` — for an AppKit label.
    /// Deliberately not a Markdown engine and deliberately dependency-free:
    /// anything richer belongs in a document, not in a 420pt-wide dialog.
    ///
    /// Bullets are always left-aligned with a hanging indent (a centered list is
    /// unreadable); plain paragraphs follow `alignment`, which keeps the
    /// first-run pitch centered exactly as it has always been. Colors are set
    /// explicitly because an attributed string ignores the label's own textColor,
    /// which would render black-on-black in dark mode.
    public static func rendered(_ markdown: String, font: NSFont,
                                alignment: NSTextAlignment = .center,
                                color: NSColor = .labelColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let blocks = parse(markdown)
        for (index, block) in blocks.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            let style = NSMutableParagraphStyle()
            style.alignment = block.isBullet ? .left : alignment
            style.lineBreakMode = .byWordWrapping
            // Space between items, not blank lines: a blank line is a full line
            // box tall and would make the window grow noticeably per bullet.
            if index < blocks.count - 1 { style.paragraphSpacing = 5 }
            if block.isBullet {
                style.headIndent = bulletIndent
                style.firstLineHeadIndent = 0
            }
            let text = block.isBullet ? bulletPrefix + block.text : block.text
            let rendered = NSMutableAttributedString(attributedString: inline(text, font: font))
            let range = NSRange(location: 0, length: rendered.length)
            rendered.addAttributes([.paragraphStyle: style, .foregroundColor: color], range: range)
            // Links have to be re-styled AFTER that blanket colour, which would otherwise
            // paint them the same as body text — clickable but indistinguishable, which is
            // the worst of both. NSTextView applies its own linkTextAttributes on top; these
            // explicit ones mean the string also reads as a link anywhere else it is drawn.
            rendered.enumerateAttribute(.link, in: range) { value, linkRange, _ in
                guard value != nil else { return }
                rendered.addAttributes([.foregroundColor: NSColor.linkColor,
                                        .underlineStyle: NSUnderlineStyle.single.rawValue],
                                       range: linkRange)
            }
            out.append(rendered)
        }
        return out
    }

    static let bulletPrefix = "• "
    private static let bulletIndent: CGFloat = 11

    /// Groups hard-wrapped source lines into blocks: a blank line ends one, a
    /// `- `/`* ` line starts a bullet, `#` headings lose their hashes, and every
    /// other line continues the block it follows (which is what lets the .md files
    /// stay wrapped at a readable width in an editor).
    private static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?
        func flush() {
            if let current, !current.text.isEmpty { blocks.append(current) }
            current = nil
        }
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let item = bulletBody(line) {
                flush()
                current = Block(text: item, isBullet: true)
            } else if line.hasPrefix("#") {
                flush()
                current = Block(text: line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces),
                                isBullet: false)
                flush()
            } else if current != nil {
                current?.text += " " + line
            } else {
                current = Block(text: line, isBullet: false)
            }
        }
        flush()
        return blocks
    }

    private static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    /// Inline Markdown only. `AttributedString(markdown:)` records emphasis as an
    /// `inlinePresentationIntent` *attribute* rather than as a bold/italic font, so
    /// the intents are mapped onto real fonts here — without that step `**bold**`
    /// parses away to nothing visible.
    private static func inline(_ text: String, font: NSFont) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(allowsExtendedAttributes: false,
                           interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)) else {
            // Unparseable markdown shows as its own source rather than vanishing.
            return NSAttributedString(string: text, attributes: [.font: font])
        }
        let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        let whole = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: font, range: whole)
        result.enumerateAttribute(.inlinePresentationIntent, in: whole) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            guard !traits.isEmpty else { return }
            result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits),
                                range: range)
        }
        return result
    }
}
