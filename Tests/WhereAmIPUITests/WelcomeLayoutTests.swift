import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The welcome window's arrangement, spacing and — above all — its HEIGHT.
///
/// The window itself lives in the App target, which is an executable with no test
/// target, so the layout was moved into WhereAmIPUI (WelcomeLayout) precisely so
/// this file could exist. What it pins:
///
///  1. Nothing is clipped. Every variant, every locale, and one deliberately
///     oversized release note on top — the copy is a bundled .md file that grows a
///     bullet at a time, and a last line that quietly falls off the bottom edge is
///     the kind of bug nobody notices until it ships.
///  2. The three bands are separated by ONE idiom (a hairline with `Space.section`
///     either side), not by a mix of gaps and rules.
///  3. A caption belongs to the row above it, by proximity — measured, not assumed.
///
/// What is NOT covered, and needs eyes, is stated at the bottom of this file.
final class WelcomeLayoutTests: XCTestCase {

    private var savedLanguageSetting: (() -> String)!
    /// Held for the duration of a test: an NSWindow whose only strong reference was
    /// a local would be free to go away mid-measurement.
    private var windows: [NSWindow] = []
    override func setUp() {
        super.setUp()
        savedLanguageSetting = L10n.languageSetting
    }
    override func tearDown() {
        L10n.languageSetting = savedLanguageSetting
        windows.removeAll()
        super.tearDown()
    }

    /// Every locale the app ships strings and welcome copy for.
    private static let locales = ["en", "de"]

    // MARK: - building one, the way the window does

    /// Builds the layout for `variant` in `locale` and lays it out in a REAL NSWindow,
    /// sized exactly the way `WelcomeWindowController` sizes its own: same four
    /// constraints, then `setContentSize(assembly.contentSize)`.
    ///
    /// A real window rather than a bare NSView on purpose. An unhosted view tree
    /// resolves under-determined widths differently from a hosted one — the badge
    /// pill, which is a plain NSView whose width comes only from its label, stretches
    /// to the full column offscreen and hugs its text in a window — so measuring
    /// outside a window would be measuring something the user never sees.
    private func laidOut(_ variant: WelcomeContent.Variant, locale: String,
                         markdown override: String? = nil)
        -> (assembly: WelcomeLayout.Assembly, container: NSView) {
        L10n.languageSetting = { locale }
        var copy = WelcomeContent.copy(variant: variant, preferredLanguages: [locale])
        if let override { copy = WelcomeContent.Copy(heading: copy.heading, markdown: override) }

        let icon = NSView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let controls = WelcomeLayout.Controls(
            launchAtLogin: NSButton(checkboxWithTitle: L10n.string(.settingsLaunchAtLogin),
                                    target: nil, action: nil),
            applications: NSButton(checkboxWithTitle: L10n.string(.settingsApplicationsLink),
                                   target: nil, action: nil),
            notify: NSButton(checkboxWithTitle: L10n.string(.settingsNotifications),
                             target: nil, action: nil),
            status: NSButton(title: "", target: nil, action: nil),
            done: NSButton(title: L10n.string(.welcomeDone), target: nil, action: nil))

        let assembly = WelcomeLayout.build(variant: variant, copy: copy, icon: icon,
                                           controls: controls)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: WelcomeLayout.windowWidth,
                                                  height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // Same as the shipped window: closing must not deallocate it out from under
        // a still-live reference (here, `windows`).
        window.isReleasedWhenClosed = false
        let container = NSView()
        window.contentView = container
        container.addSubview(assembly.stack)
        NSLayoutConstraint.activate([
            assembly.stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            assembly.stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            assembly.stack.topAnchor.constraint(equalTo: container.topAnchor),
            assembly.stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        window.setContentSize(assembly.contentSize)
        container.layoutSubtreeIfNeeded()
        windows.append(window)
        return (assembly, container)
    }

    /// A view's frame in the container's coordinates. NSView is not flipped, so
    /// "inside the window" means `minY >= 0 && maxY <= container height` — a slot
    /// that hangs off the bottom edge has a NEGATIVE minY, which is exactly the
    /// failure this file exists to catch.
    private func rect(_ view: NSView, in container: NSView) -> NSRect {
        view.convert(view.bounds, to: container)
    }

    /// A view's ALIGNMENT rect in the container's coordinates — what Auto Layout and
    /// NSStackView actually line up, and what the eye reads as the edge. A checkbox's
    /// frame is a couple of points wider than its alignment rect on every side, so
    /// comparing raw frames would measure the control's invisible padding rather than
    /// where its glyph and its title sit.
    private func aligned(_ view: NSView, in container: NSView) -> NSRect {
        view.alignmentRect(forFrame: rect(view, in: container))
    }

    /// Names a slot in a failure message by what it says, so "something is clipped"
    /// arrives as "the privacy line is clipped".
    private func describe(_ view: NSView) -> String {
        if let field = view as? NSTextField {
            let text = field.stringValue.isEmpty ? field.attributedStringValue.string : field.stringValue
            return "\"\(text.prefix(40))\""
        }
        if let button = view as? NSButton { return "checkbox \"\(button.title)\"" }
        return "\(type(of: view))"
    }

    // MARK: - 1. nothing is clipped

    /// The one correctness assertion: for every variant and every locale, the height
    /// the layout hands the window is enough for all of its content, and every slot
    /// that draws text is at its full intrinsic height and wholly inside the window.
    func testNothingIsClipped_everyVariantEveryLocale() {
        for variant in WelcomeContent.Variant.allCases {
            for locale in Self.locales {
                let (assembly, container) = laidOut(variant, locale: locale)
                let where_ = "\(variant) / \(locale)"

                XCTAssertEqual(assembly.stack.frame.height, container.frame.height, accuracy: 0.5,
                               "\(where_): the stack does not fill the height it asked for — "
                               + "it is either compressed or hanging out of the window")

                for slot in assembly.textSlots {
                    let frame = rect(slot, in: container)
                    let needed = slot.intrinsicContentSize.height
                    if needed > 0 {
                        XCTAssertGreaterThanOrEqual(
                            frame.height, needed - 0.5,
                            "\(where_): \(describe(slot)) is \(frame.height)pt tall but needs "
                            + "\(needed)pt — a line of it is being cut off")
                    }
                    XCTAssertGreaterThanOrEqual(frame.minY, -0.5,
                                                "\(where_): \(describe(slot)) hangs off the bottom edge")
                    XCTAssertLessThanOrEqual(frame.maxY, container.frame.height + 0.5,
                                             "\(where_): \(describe(slot)) is above the top edge")
                }

                // The last thing in the window, and the one a clipped window loses
                // first: the button the reader is supposed to press.
                let done = rect(assembly.doneButton, in: container)
                XCTAssertEqual(done.minY, WelcomeLayout.Space.margin, accuracy: 0.5,
                               "\(where_): Done is not sitting one margin above the bottom edge")
            }
        }
    }

    /// The same guarantee against copy nobody has written yet. The body is a bundled
    /// Markdown file that grows a bullet at a time; the window has to answer that by
    /// being taller, never by cropping. Three times the longest shipped release note
    /// is far past anything reasonable — and it still lays out whole.
    func testAnyReasonableMarkdownLengthLaysOutUncropped() {
        let real = WelcomeContent.markdown(milestone: welcomeMilestone, preferredLanguages: ["de"])
        for multiple in [2, 3] {
            let long = Array(repeating: real, count: multiple).joined(separator: "\n")
            let (assembly, container) = laidOut(.whatsNew, locale: "de", markdown: long)
            XCTAssertEqual(assembly.body.frame.height, assembly.body.intrinsicContentSize.height,
                           accuracy: 0.5, "\(multiple)× the release note gets cropped")
            XCTAssertGreaterThanOrEqual(rect(assembly.doneButton, in: container).minY,
                                        WelcomeLayout.Space.margin - 0.5,
                                        "\(multiple)× the release note pushes Done out of the window")
            XCTAssertGreaterThan(container.frame.height, WelcomeLayout.windowWidth,
                                 "a \(multiple)× body should have made the window taller")
        }
    }

    /// A height budget, in points, that the shipped copy has to stay inside.
    ///
    /// "The window may be taller for longer content" only holds while the window
    /// still fits on a screen. Past that AppKit clamps it, and this window has no
    /// scroll view — the overflow is simply gone. The hard ceiling: the smallest
    /// logical screen among the Macs macOS 13 supports is 1440×900 at default
    /// scaling, which leaves ~875pt of visible frame once the menu bar is gone, and
    /// the title bar takes ~28 of that — so ~845pt of content is where the window
    /// stops fitting. This budget sits a line or two under that, because the number
    /// that actually grows is somebody's German translation.
    ///
    /// The tallest shipped combination is what's-new in German. If a future release
    /// note trips this, the copy is too long for the window — trimming it is the
    /// decision to take, not raising the number.
    func testTheTallestShippedVariantStaysInsideTheHeightBudget() {
        let budget: CGFloat = 820
        for variant in WelcomeContent.Variant.allCases {
            for locale in Self.locales {
                let height = laidOut(variant, locale: locale).assembly.contentHeight
                XCTAssertLessThanOrEqual(height, budget,
                                         "\(variant) / \(locale) needs \(Int(height))pt of content "
                                         + "height — past the \(Int(budget))pt budget")
            }
        }
    }

    // MARK: - 2. three bands, one separation idiom

    /// Content → setup → footer, told by exactly two hairlines, each with
    /// `Space.section` above and below. One idiom, used consistently: no band is
    /// separated by a gap alone while another gets a rule.
    func testTheTwoBandSeparatorsCarryTheScalesSectionGapOnBothSides() {
        for variant in WelcomeContent.Variant.allCases {
            let (assembly, container) = laidOut(variant, locale: "en")
            XCTAssertEqual(assembly.separators.count, 2,
                           "\(variant): three bands need exactly two rules")

            // Above the first rule: the last thing in the content band — the notch
            // aside where it is shown, the body where it is not.
            let contentTail = assembly.hint ?? assembly.body
            let pairs: [(String, NSView, NSView)] = [
                ("content → rule", contentTail, assembly.separators[0]),
                ("rule → setup", assembly.separators[0], assembly.setupSection),
                ("setup → rule", assembly.setupSection, assembly.separators[1]),
                ("rule → footer", assembly.separators[1], assembly.privacy),
            ]
            for (name, above, below) in pairs {
                let gap = rect(above, in: container).minY - rect(below, in: container).maxY
                XCTAssertEqual(gap, WelcomeLayout.Space.section, accuracy: 0.5,
                               "\(variant): \(name) is \(gap)pt, not the scale's section gap")
            }
            for rule in assembly.separators {
                XCTAssertEqual(rule.frame.height, WelcomeLayout.separatorThickness, accuracy: 0.5,
                               "\(variant): the band rule is not a hairline")
                XCTAssertEqual(rule.frame.width, WelcomeLayout.contentWidth, accuracy: 0.5,
                               "\(variant): the band rule does not span the content column")
            }
        }
    }

    /// The footer is one group, anchored to the bottom edge: privacy line, then
    /// `Space.related` to Done, then one margin to the window's edge. It used to be
    /// 24 and 24, which left the privacy line floating exactly halfway between the
    /// setup section and the button and belonging to neither.
    func testTheFooterIsOneGroupAnchoredToTheBottomMargin() {
        let (assembly, container) = laidOut(.intro, locale: "en")
        let privacy = rect(assembly.privacy, in: container)
        let done = rect(assembly.doneButton, in: container)
        XCTAssertEqual(privacy.minY - done.maxY, WelcomeLayout.Space.related, accuracy: 0.5,
                       "the privacy line is not grouped with the button it belongs to")
        XCTAssertEqual(done.minY, WelcomeLayout.Space.margin, accuracy: 0.5,
                       "the bottom margin does not match the side margins")
        XCTAssertLessThan(privacy.minY - done.maxY,
                          rect(assembly.separators[1], in: container).minY - privacy.maxY,
                          "the privacy line is closer to the rule above it than to its own button")
    }

    // MARK: - 3. captions belong to their row

    /// Proximity has to answer "which checkbox is this caption about" without the
    /// reader thinking. So: the caption sits `Space.bound` under its own row while
    /// the rows sit `Space.group` apart — strictly closer to its own — and its left
    /// edge lines up with the checkbox TITLES, not with their squares.
    func testTheNotifyCaptionBelongsToItsOwnRowAndNotToItsNeighbour() {
        let (assembly, container) = laidOut(.intro, locale: "en")
        let notify = aligned(assembly.checkboxes[2], in: container)
        let caption = aligned(assembly.notifyCaption, in: container)
        let rowAbove = aligned(assembly.checkboxes[1], in: container)

        let toOwnRow = notify.minY - caption.maxY
        let betweenRows = rowAbove.minY - notify.maxY
        XCTAssertEqual(toOwnRow, WelcomeLayout.Space.bound, accuracy: 0.5,
                       "the caption is not bound to its checkbox")
        XCTAssertEqual(betweenRows, WelcomeLayout.Space.group, accuracy: 0.5,
                       "the checkbox rows are not on the scale's group gap")
        XCTAssertLessThan(toOwnRow, betweenRows,
                          "the caption is no closer to its own row than the rows are to each other")

        XCTAssertEqual(caption.minX - notify.minX, WelcomeLayout.checkboxTextIndent, accuracy: 0.5,
                       "the caption is not indented under the checkbox's label")
        // The shared status slot shares that one left edge, so the section has a
        // single secondary-text column rather than two competing ones.
        XCTAssertEqual(aligned(assembly.statusSlot, in: container).minX, caption.minX, accuracy: 0.5,
                       "the status slot does not share the caption's left edge")
    }

    /// Only the notifications row gets a caption. Reserving aligned caption space
    /// under all three would be two permanently blank slots — the exact "hole" two
    /// earlier reviews of this window flagged and fixed.
    func testOnlyTheNotificationsRowCarriesACaption() {
        let (assembly, container) = laidOut(.intro, locale: "en")
        let rows = assembly.checkboxes.map { aligned($0, in: container) }
        XCTAssertEqual(rows[0].minY - rows[1].minY, rows[1].minY - rows[2].minY, accuracy: 0.5,
                       "the three checkbox rows are not on one consistent pitch")
    }

    /// The header carries the pattern and the caption carries the explanation — the
    /// same split the app's menu rows make. The header is set the way the badges are
    /// (uppercase, tracked, locale-aware) and no longer drags a parenthetical along
    /// beside it.
    func testTheSetupHeaderIsASectionHeaderAndItsExplanationIsACaptionBeneathIt() {
        for locale in Self.locales {
            let (assembly, container) = laidOut(.intro, locale: locale)
            let source = L10n.string(.welcomeSetupHeader)
            XCTAssertEqual(assembly.setupHeader.stringValue, source.localizedUppercase,
                           "\(locale): the section header is not uppercased by the view")
            XCTAssertNotEqual(source, source.localizedUppercase,
                              "\(locale) stores the header already uppercased — that belongs in the view")
            XCTAssertFalse(assembly.setupCaption.stringValue.contains("("),
                           "\(locale): the explanation is still a parenthetical, not a caption")

            let header = aligned(assembly.setupHeader, in: container)
            let caption = aligned(assembly.setupCaption, in: container)
            XCTAssertEqual(header.minY - caption.maxY, WelcomeLayout.Space.bound, accuracy: 0.5,
                           "\(locale): the caption is not bound to its header")
            XCTAssertEqual(header.minX, caption.minX, accuracy: 0.5,
                           "\(locale): header and caption do not share a left edge")
            XCTAssertEqual(header.minX, aligned(assembly.checkboxes[0], in: container).minX,
                           accuracy: 0.5,
                           "\(locale): the section header does not start where its rows start")
        }
    }

    // MARK: - the notch aside

    /// It is first-run orientation — where to look for the flag — so it belongs to
    /// the pitch and to nothing else. In the what's-new window it was a paragraph of
    /// first-run copy wedged between a change log and a settings group, jammed 6pt
    /// under the last bullet's descenders.
    func testTheNotchAsideIsPitchCopyAndAppearsOnlyThere() {
        XCTAssertTrue(WelcomeContent.showsNotchHint(variant: .intro))
        XCTAssertFalse(WelcomeContent.showsNotchHint(variant: .whatsNew))
        XCTAssertNotNil(laidOut(.intro, locale: "en").assembly.hint)
        XCTAssertNil(laidOut(.whatsNew, locale: "en").assembly.hint)
    }

    /// Where it does appear it is a footnote, not a sixth bullet: `Space.related` of
    /// air under the body (it used to be 6pt, which put an 11pt line inside the 12pt
    /// body's descenders) and quieter than the copy it follows.
    func testTheNotchAsideIsSetAsAQuietFootnoteUnderTheBody() {
        let (assembly, container) = laidOut(.intro, locale: "en")
        let hint = try? XCTUnwrap(assembly.hint)
        guard let hint else { return }
        XCTAssertEqual(rect(assembly.body, in: container).minY - rect(hint, in: container).maxY,
                       WelcomeLayout.Space.related, accuracy: 0.5,
                       "the aside is not given its own breathing room under the body")
        XCTAssertEqual(hint.textColor, .secondaryLabelColor)
        XCTAssertLessThan(hint.font!.pointSize, assembly.body.font!.pointSize,
                          "the aside is set as loud as the copy it is an aside to")
    }

    // MARK: - the scale itself

    /// Five values, and they are the five the window actually uses. A sixth ad-hoc
    /// number is how the previous layout ended up with 2, 4, 6, 8, 12, 20 and 24 gaps
    /// that no longer meant anything in particular.
    func testTheSpacingScaleIsStrictlyAscendingAndSmall() {
        let scale = [WelcomeLayout.Space.bound, WelcomeLayout.Space.group,
                     WelcomeLayout.Space.related, WelcomeLayout.Space.section,
                     WelcomeLayout.Space.margin]
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertEqual(Set(scale).count, scale.count)
        XCTAssertEqual(WelcomeLayout.contentWidth,
                       WelcomeLayout.windowWidth - WelcomeLayout.Space.margin * 2,
                       "the content column no longer follows the window's own margins")
    }

    // MARK: - not covered here, needs eyes
    //
    //  - Whether two hairlines are the right amount of structure for the SHORT
    //    (intro) variant, where the bands are only a few lines each. Measured, they
    //    are consistent; whether they read as calm or as fussy is a judgement.
    //  - The uppercase section header against the uppercase badge, ~200pt apart in
    //    the same window: the tint and the weight are meant to keep them from
    //    reading as two of the same thing. Only eyes can confirm that.
    //  - Whether dropping the notch aside from the what's-new window loses anything
    //    a returning reader wanted.
}
