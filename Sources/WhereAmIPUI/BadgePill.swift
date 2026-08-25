import AppKit

/// The welcome window's category pill: a small rounded-rect badge with uppercase,
/// letter-spaced text on a soft tinted background, sitting between the app icon and
/// the heading.
///
/// It exists because the heading used to carry the category ("Welcome to WhereAmIP
/// v0.6", "WhereAmIP v0.6 — what's new") and paid for it in length, in a window
/// whose whole layout is a tuned arrangement of fixed slots. The badge says the
/// same thing in a shape that reads at a glance, which let both headings slim down
/// to one shared "WhereAmIP v%@".
///
/// Lives in WhereAmIPUI rather than inline in WelcomeWindow for the same blunt
/// reason WelcomeContent does: the App target is an executable with no test target,
/// and "which words and which tint does each variant get" is exactly the part that
/// must not regress silently. The window itself only places whatever this hands back.
///
/// Both the text colour and the background tint come from dynamic system colours and
/// are resolved at DRAW time, never baked into a CGColor: a `layer.backgroundColor`
/// is a resolved `CGColor` and would keep the light-mode fill after the user switches
/// to dark. `draw(_:)` runs with the view's effective appearance current, so the same
/// `NSColor` paints correctly in both — see BadgePillTests, which pins that the tints
/// really do resolve to different RGB under aqua and darkAqua.
public final class BadgePill: NSView {

    /// 11pt bold: small enough to read as a label rather than a second heading, bold
    /// enough to survive the uppercasing and the letter spacing below.
    public static let font = NSFont.systemFont(ofSize: 11, weight: .bold)
    /// Letter spacing as a fraction of the point size (~0.08em) — uppercase text set
    /// solid is noticeably harder to read, and tracking is the standard remedy.
    /// Public because the welcome window sets its section headers uppercase too and
    /// has to track them the same way (see WelcomeLayout.sectionHeader): one number,
    /// not two free to drift apart in the same window.
    public static let kernRatio: CGFloat = 0.08
    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 4
    /// Background opacity for the tint. Low enough that the pill stays a background
    /// and the 11pt text on top of it stays the thing you read.
    private static let backgroundAlpha: CGFloat = 0.15

    /// The pill's height, and it is a CONSTANT: the welcome window sizes itself once,
    /// at open, from its stack's fitting size, so a row whose height depended on its
    /// text (or on the locale) would move every slot below it. Derived from the font's
    /// own line height rather than guessed at, so changing the font above keeps the
    /// padding honest instead of silently clipping.
    public static let height: CGFloat =
        ceil(NSLayoutManager().defaultLineHeight(for: font)) + verticalPadding * 2

    /// The dynamic system colour this pill is drawn in — full strength for the text,
    /// `backgroundAlpha` for the fill, so the two can never drift apart.
    public let tint: NSColor
    /// What the pill actually shows: the localized title-case source, uppercased.
    public let text: String

    public init(text source: String, tint: NSColor) {
        self.tint = tint
        // Locale-aware, not `uppercased()`: the strings file stores title case and the
        // view uppercases, the same split SwiftUI's `.textCase(.uppercase)` makes.
        self.text = source.localizedUppercase
        super.init(frame: .zero)

        // `labelWithAttributedString:` is the non-wrapping, NON-SELECTABLE factory —
        // the same reason ReadingLabel exists next door. A selectable field hands
        // attributed text to the window's field editor on click and gets back the
        // flattened plain string, which here would drop the kerning and the colour.
        let label = NSTextField(labelWithAttributedString: NSAttributedString(
            string: self.text,
            attributes: [.font: Self.font,
                         .kern: Self.font.pointSize * Self.kernRatio,
                         // Explicit: an attributed string ignores the field's own
                         // textColor, which would render black-on-black in dark mode.
                         .foregroundColor: tint]))
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        // Width follows the label (plus padding); height never does.
        setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Fully rounded ends (radius = height/2), which is what makes it read as a pill
    /// rather than as a tag or a button.
    public override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        tint.withAlphaComponent(Self.backgroundAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    /// The pill for a welcome-window variant: the words and the tint in one place, so
    /// the window's own code is a single call and neither half can be changed alone.
    ///
    /// Blue for the pitch, amber for the highlights — deliberately `.systemBlue`
    /// rather than `.controlAccentColor`: the accent colour is the user's to choose,
    /// and a graphite or an orange accent would leave the two badges telling the same
    /// story in the same colour. These two are picked as a PAIR.
    public static func forVariant(_ variant: WelcomeContent.Variant) -> BadgePill {
        switch variant {
        case .intro:
            return BadgePill(text: L10n.string(.welcomeBadgeIntro), tint: .systemBlue)
        case .whatsNew:
            return BadgePill(text: L10n.string(.welcomeBadgeWhatsNew), tint: .systemOrange)
        }
    }
}
