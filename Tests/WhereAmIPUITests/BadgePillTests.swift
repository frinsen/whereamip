import XCTest
@testable import WhereAmIPUI

/// The welcome window's category pill.
///
/// The window that places it lives in the App target, which is an executable with no
/// test target — so everything about the badge that can regress silently (its words
/// per variant per locale, its tints, and above all its FIXED height, on which the
/// window's one-shot sizing pass depends) is decided in WhereAmIPUI and pinned here.
/// What is NOT covered, and needs eyes, is stated at the bottom of this file.
final class BadgePillTests: XCTestCase {

    // The lookup-based assertions below go through L10n, so the language override is
    // pinned for the same reason L10nTests pins it: a host Mac left on Settings ▸
    // Language ▸ Deutsch would otherwise leak that choice into the suite.
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

    /// The `.lproj` bundle for `locale`, resolved out of the located UI bundle —
    /// deliberately NOT `L10n.string`, which answers in whatever language the setting
    /// says, so a German assertion holds on an English machine and vice versa.
    func bundle(for locale: String) throws -> Bundle {
        let path = try XCTUnwrap(uiResourceBundle.path(forResource: locale, ofType: "lproj"),
                                 "\(locale).lproj is missing from the resource bundle")
        return try XCTUnwrap(Bundle(path: path))
    }
    func value(_ key: L10nKey, in bundle: Bundle) -> String {
        bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
    }

    // MARK: - the words, per variant, per locale

    func testBadgeTextPerVariantPerLocale() throws {
        let en = try bundle(for: "en")
        let de = try bundle(for: "de")
        XCTAssertEqual(value(.welcomeBadgeIntro, in: en), "Getting Started")
        XCTAssertEqual(value(.welcomeBadgeWhatsNew, in: en), "What's New")
        XCTAssertEqual(value(.welcomeBadgeIntro, in: de), "Erste Schritte")
        // The same words Settings ▸ What's New uses — Apple's own wording for the
        // section — so the entry and the window it opens name the same thing.
        XCTAssertEqual(value(.welcomeBadgeWhatsNew, in: de), value(.settingsWhatsNew, in: de))
        XCTAssertEqual(value(.welcomeBadgeWhatsNew, in: de), "Neue Funktionen")
    }

    /// Title case in the strings file, uppercase on screen: the split is the view's,
    /// so the file stays readable and a translator never has to shout.
    func testTheViewUppercasesWhatTheStringsFileStoresInTitleCase() throws {
        for locale in ["en", "de"] {
            let source = value(.welcomeBadgeIntro, in: try bundle(for: locale))
            XCTAssertNotEqual(source, source.localizedUppercase,
                              "\(locale) stores the badge already uppercased — that belongs in the view")
            XCTAssertEqual(BadgePill(text: source, tint: .systemBlue).text, source.localizedUppercase)
        }
    }

    func testEachVariantGetsItsOwnWordsAndItsOwnTint() {
        let intro = BadgePill.forVariant(.intro)
        let whatsNew = BadgePill.forVariant(.whatsNew)
        XCTAssertEqual(intro.text, L10n.string(.welcomeBadgeIntro).localizedUppercase)
        XCTAssertEqual(whatsNew.text, L10n.string(.welcomeBadgeWhatsNew).localizedUppercase)
        XCTAssertNotEqual(intro.text, whatsNew.text)
        XCTAssertEqual(intro.tint, .systemBlue)
        XCTAssertEqual(whatsNew.tint, .systemOrange)
        XCTAssertNotEqual(intro.tint, whatsNew.tint,
                          "the two badges would be telling different stories in the same colour")
    }

    // MARK: - light AND dark mode

    /// The requirement is "must look right in light AND dark", and the way to fail it
    /// is a hardcoded RGB (or a resolved `CGColor` baked into a layer). Both tints are
    /// therefore asserted to be genuinely DYNAMIC: the same NSColor has to resolve to
    /// different sRGB values under aqua and darkAqua. A literal colour resolves the
    /// same under both and fails right here.
    func testBothTintsAreDynamicSystemColoursNotBakedRGB() throws {
        func rgb(_ color: NSColor, under name: NSAppearance.Name) throws -> [CGFloat] {
            var components: [CGFloat] = []
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                guard let srgb = color.usingColorSpace(.sRGB) else { return }
                components = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            }
            return components
        }
        for variant in WelcomeContent.Variant.allCases {
            let tint = BadgePill.forVariant(variant).tint
            let light = try rgb(tint, under: .aqua)
            let dark = try rgb(tint, under: .darkAqua)
            XCTAssertEqual(light.count, 3, "\(variant) tint did not resolve to sRGB")
            XCTAssertNotEqual(light, dark,
                              "\(variant) tint is the same in light and dark — that is a hardcoded colour")
        }
    }

    /// One step past "the colours are dynamic": the pill is actually PAINTED, it is
    /// painted as a pill, and it paints differently in the two appearances. Cheap
    /// insurance against the classic version of this view — a `layer.backgroundColor`,
    /// which is a resolved CGColor and would keep the light-mode fill after a switch
    /// to dark — and against a `draw(_:)` that silently stops being called at all.
    func testThePillIsDrawn_RoundedTintedAndDifferentInDarkMode() throws {
        func render(_ pill: BadgePill, under name: NSAppearance.Name) throws -> NSBitmapImageRep {
            pill.frame = NSRect(origin: .zero, size: pill.fittingSize)
            pill.appearance = NSAppearance(named: name)
            let rep = try XCTUnwrap(pill.bitmapImageRepForCachingDisplay(in: pill.bounds))
            pill.cacheDisplay(in: pill.bounds, to: rep)
            return rep
        }
        func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
            try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        let light = try render(BadgePill.forVariant(.whatsNew), under: .aqua)
        let dark = try render(BadgePill.forVariant(.whatsNew), under: .darkAqua)

        // Middle of the left cap: inside the pill, but left of the text.
        let inside = try pixel(light, 3, light.pixelsHigh / 2)
        XCTAssertGreaterThan(inside.alphaComponent, 0.05, "nothing was painted inside the pill")
        XCTAssertGreaterThan(inside.redComponent, inside.blueComponent,
                             "the what's-new fill is amber, not whatever this is")

        // Top-left corner: outside a radius = height/2 round-rect, so it stays clear —
        // this is what makes it a pill rather than a rectangle.
        XCTAssertLessThan(try pixel(light, 0, 0).alphaComponent, 0.05,
                          "the corner is filled — the shape is not rounded")

        let insideDark = try pixel(dark, 3, dark.pixelsHigh / 2)
        func triple(_ c: NSColor) -> [CGFloat] { [c.redComponent, c.greenComponent, c.blueComponent] }
        XCTAssertNotEqual(triple(inside), triple(insideDark),
                          "the fill is identical in light and dark — it was baked, not resolved at draw time")
    }

    // MARK: - the layout guard: one new row, of a height that never moves

    /// The welcome window sizes itself ONCE, at open, from its stack's fitting size.
    /// A badge whose height followed its text — a longer German word, a wider locale,
    /// a future third variant — would move every slot below it. So the height is a
    /// constant and the width is the only thing allowed to vary.
    func testHeightIsAConstantWhileOnlyTheWidthFollowsTheText() {
        let short = BadgePill(text: "Hi", tint: .systemBlue)
        let long = BadgePill(text: "Neue Funktionen und noch viel mehr", tint: .systemOrange)
        for pill in [short, long] {
            XCTAssertEqual(pill.fittingSize.height, BadgePill.height, "\(pill.text) is off-height")
        }
        XCTAssertGreaterThan(long.fittingSize.width, short.fittingSize.width,
                             "the pill must still hug its own text horizontally")
    }

    /// The same fact one level up, where it actually bites: dropped into a vertical
    /// NSStackView the way the welcome window drops it in, the badge contributes
    /// exactly `BadgePill.height` plus the gap after it — the ONLY growth the window
    /// takes on, with every other slot's spacing untouched.
    func testInAStackTheBadgeRowCostsExactlyItsHeightPlusItsGap() {
        let gap: CGFloat = 6   // WelcomeWindow.badgeGap
        func fittingHeight(withBadge: Bool) -> CGFloat {
            let icon = NSView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
            let heading = NSTextField(labelWithString: "WhereAmIP v9.9")
            heading.font = .boldSystemFont(ofSize: 15)
            var views: [NSView] = [icon, heading]
            var badge: BadgePill?
            if withBadge {
                let pill = BadgePill.forVariant(.whatsNew)
                badge = pill
                views.insert(pill, at: 1)
            }
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 12
            stack.setCustomSpacing(8, after: icon)
            if let badge { stack.setCustomSpacing(gap, after: badge) }
            stack.layoutSubtreeIfNeeded()
            return stack.fittingSize.height
        }
        XCTAssertEqual(fittingHeight(withBadge: true) - fittingHeight(withBadge: false),
                       BadgePill.height + gap, accuracy: 0.5)
    }

    /// The pill sits in the same 372pt content column as everything else in the
    /// window. It is short by design, but German runs long almost by default, so this
    /// is measured rather than assumed — for every shipped locale, both variants.
    func testEveryLocalesBadgeFitsTheWindowContentWidth() throws {
        let available: CGFloat = 372   // 420 window width - 24*2 edge insets
        for locale in ["en", "de"] {
            let bundle = try self.bundle(for: locale)
            for key in [L10nKey.welcomeBadgeIntro, .welcomeBadgeWhatsNew] {
                let pill = BadgePill(text: value(key, in: bundle), tint: .systemBlue)
                XCTAssertLessThanOrEqual(pill.fittingSize.width, available,
                                         "\(locale) \(key.rawValue) is \(Int(pill.fittingSize.width))pt wide, "
                                         + "over the \(Int(available))pt column: \(pill.text)")
            }
        }
    }

    /// Reading copy, not a control: nothing here offers an interaction, and a
    /// selectable field would hand the attributed string to the window's field editor
    /// on click and get back the flattened plain text — kerning and colour gone. Same
    /// rule, same reason, as ReadingLabel next door.
    func testTheBadgeLabelIsInertReadingCopy() throws {
        let label = try XCTUnwrap(BadgePill.forVariant(.intro).subviews.first as? NSTextField)
        XCTAssertFalse(label.isSelectable)
        XCTAssertFalse(label.isEditable)
        XCTAssertEqual(label.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat,
                       BadgePill.font.pointSize * 0.08,
                       "uppercase text set solid is what the letter spacing is there to fix")
    }

    // MARK: - what this file cannot see
    //
    // Headless AppKit measures, it does not look. Still needs the maintainer's eyes,
    // in BOTH appearances and BOTH languages (Settings ▸ Show Welcome Window and
    // Settings ▸ What's New in a built .app):
    //   • that the pill actually sits between the icon and the heading, centred, and
    //     that the 8pt/6pt gaps around it read as one group rather than three;
    //   • that a 15%-alpha fill is visible-but-quiet on the window's material in dark
    //     mode as well as light (the alpha is the one number no assertion can judge);
    //   • that 11pt bold uppercase at 0.08em is legible rather than cramped at the
    //     Mac's actual rendering.
}
