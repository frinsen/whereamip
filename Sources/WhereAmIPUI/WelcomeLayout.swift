import AppKit

/// The welcome window's layout: every view it stacks, every gap between them, and
/// the height the window has to be so none of it is cut off.
///
/// It lives in WhereAmIPUI, not next to the NSWindowController, for the same blunt
/// reason WelcomeContent and BadgePill do: the App target is an executable with no
/// test target, and "does the copy actually fit" is exactly the kind of thing that
/// regresses silently — a longer release note, a longer German string, one more
/// bullet. `WelcomeWindowController` now owns only the window, the three live
/// toggles and their actions; everything about arrangement and size is decided
/// here, where `WelcomeLayoutTests` can measure it.
///
/// # Three bands
///
/// The window reads as content → setup → footer, and it says so with a hairline
/// rule between each pair of bands, `Space.section` of air either side. That is
/// ONE idiom used twice, deliberately not mixed with "generous gaps here, a rule
/// there" — the previous layout separated its bands with nothing but gaps of 24
/// and 20, which at this window's height (the what's-new variant runs past 700pt)
/// did not read as structure at all: the notch hint looked like it belonged to the
/// checkboxes, and the privacy line floated between the setup group and the Done
/// button with nothing to attach to.
///
/// # One spacing scale
///
/// Every gap in the window is one of five values (see `Space`), chosen by what the
/// gap MEANS rather than by eye. Proximity is the whole point of the scale: a
/// caption sits `bound` (4) from the row it explains while rows sit `group` (8)
/// apart, so a caption can never read as belonging to the row below it. The one
/// gap that is off the scale — the 6pt badge→heading — belongs to the already
/// approved top half of the window and is left exactly as it shipped (`badgeGap`).
public enum WelcomeLayout {

    /// The window's spacing scale. Five values, each with one job:
    ///
    /// - `bound` (4): a caption and the thing it explains. Nothing else.
    /// - `group` (8): sibling rows inside one group (the three checkboxes).
    /// - `related` (12): two blocks that belong to the same section but are not
    ///   the same kind of thing (a section's header block and its rows; the
    ///   privacy line and the Done button).
    /// - `section` (16): air around a band separator, and the window's top inset.
    ///   Deliberately not larger: the hairline is what separates the bands, so
    ///   padding it out as well would be saying the same thing twice — in a window
    ///   whose tallest variant is already close to the height of the shortest
    ///   screen this app runs on (see `WelcomeLayoutTests`' height budget).
    /// - `margin` (24): the window's own edges. The bottom margin must never be
    ///   smaller than the sides, so the footer's last gap is this and not
    ///   `section`.
    ///
    /// Every value is a multiple of 4, which is what stops a sixth one being
    /// invented the next time something "needs a bit more air".
    public enum Space {
        public static let bound: CGFloat = 4
        public static let group: CGFloat = 8
        public static let related: CGFloat = 12
        public static let section: CGFloat = 16
        public static let margin: CGFloat = 24
    }

    /// Fixed window width — this is an informational dialog, not a resizable one.
    public static let windowWidth: CGFloat = 420
    /// Usable width inside the side margins. Every wrapping label's
    /// `preferredMaxLayoutWidth`, and the fixed width of the setup section.
    public static let contentWidth: CGFloat = windowWidth - Space.margin * 2   // 372

    /// Approximates the leading edge of a standard AppKit checkbox's title text
    /// (glyph + its gap before the label) — not pixel-exact across every
    /// rendering, but close enough to align a caption under the checkbox's
    /// *label* rather than under its square.
    public static let checkboxTextIndent: CGFloat = 19

    /// Fixed height for the conditionally-populated status slot — EXACTLY two
    /// lines at its 10pt font (`NSLayoutManager.defaultLineHeight` measures 12pt
    /// a line). The slot never leaves the stack and is never `.isHidden`, so the
    /// window's size cannot depend on whether an error or a permission hint
    /// happens to be showing; a looser reservation than "exactly two lines" read
    /// as a hole in an earlier design review.
    public static let reservedStatusLineHeight: CGFloat = 24

    /// Badge → heading, from the approved top half: the badge names the category
    /// the heading no longer spells out, so the two belong together — tighter
    /// than the stack's 12pt default, looser than the 4pt binding the heading to
    /// its body. Off the scale on purpose, and left where it shipped.
    public static let badgeGap: CGFloat = 6

    /// A hairline is a hairline. `NSBox(boxType: .separator)` is NOT one: it lays
    /// out 5pt tall with the rule drawn somewhere inside, which turns a measured
    /// 16pt gap into a visual 18pt one and quietly costs 8pt of window height for
    /// nothing. The band rules are custom-filled boxes of exactly this height.
    public static let separatorThickness: CGFloat = 1

    // MARK: - inputs

    /// The interactive views the window owns, because they carry its targets and
    /// actions. The layout places them; it never builds them and never reads or
    /// writes their state.
    public struct Controls {
        public let launchAtLogin: NSButton
        public let applications: NSButton
        public let notify: NSButton
        /// Shared conditional-status slot (applications-link error OR the
        /// notifications-denied hint). Both of its axes get pinned to constants
        /// here — see `reservedStatusLineHeight`.
        public let status: NSButton
        public let done: NSButton

        public init(launchAtLogin: NSButton, applications: NSButton, notify: NSButton,
                    status: NSButton, done: NSButton) {
            self.launchAtLogin = launchAtLogin
            self.applications = applications
            self.notify = notify
            self.status = status
            self.done = done
        }
    }

    // MARK: - output

    /// The assembled stack plus the non-interactive views inside it, handed back
    /// by name so the tests can measure the arrangement instead of re-deriving
    /// it. The window itself only needs `stack` and `contentHeight`.
    public struct Assembly {
        public let stack: NSStackView
        public let icon: NSView
        public let badge: BadgePill
        public let heading: NSTextField
        public let body: NSTextField
        /// nil in the what's-new variant, which does not show the notch hint —
        /// see `WelcomeContent.showsNotchHint(variant:)`.
        public let hint: NSTextField?
        /// The whole setup band, so callers measuring the band gaps do not have to
        /// go spelunking through `superview`.
        public let setupSection: NSStackView
        public let setupHeader: NSTextField
        public let setupCaption: NSTextField
        public let checkboxes: [NSButton]
        public let notifyCaption: NSTextField
        public let statusSlot: NSButton
        public let privacy: NSTextField
        public let doneButton: NSButton
        /// Exactly two, in top-to-bottom order: content|setup, setup|footer.
        public let separators: [NSBox]

        /// Every view that draws text it would be a bug to cut off — i.e. everything
        /// whose height has to survive intact for the window to be honest.
        public var textSlots: [NSView] {
            ([heading, body, hint, setupHeader, setupCaption,
              notifyCaption, privacy] as [NSView?]).compactMap { $0 }
            + checkboxes + [doneButton]
        }

        /// The content height the window must be given so nothing is clipped.
        /// Resolved by Auto Layout from the real, already-rendered views — not
        /// estimated — which is what lets a longer release note (or a longer
        /// German string) simply open a taller window.
        public var contentHeight: CGFloat {
            stack.layoutSubtreeIfNeeded()
            return ceil(stack.fittingSize.height)
        }

        public var contentSize: NSSize { NSSize(width: windowWidth, height: contentHeight) }
    }

    // MARK: - assembly

    /// Builds the whole window body for `variant` and `copy`, around the caller's
    /// `icon` view and `controls`.
    public static func build(variant: WelcomeContent.Variant,
                             copy: WelcomeContent.Copy,
                             icon: NSView,
                             controls: Controls) -> Assembly {
        // MARK: content band — badge, heading, body, and (intro only) the aside

        let badge = BadgePill.forVariant(variant)

        let heading = NSTextField(labelWithString: copy.heading)
        heading.font = .boldSystemFont(ofSize: 15)
        heading.alignment = .center

        // Bundled Markdown, rendered once, before the window is ever shown — so a
        // longer what's-new body resolves into a taller window at open and never
        // resizes afterwards. ReadingLabel, not the raw wrapping-label factory:
        // that one is selectable, and a click on selectable attributed text hands
        // it to the window's field editor, which writes the flattened plain string
        // back — bold gone, bullet indents collapsed, permanently.
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let body = ReadingLabel.wrapping(font: bodyFont)
        body.attributedStringValue = WelcomeContent.rendered(copy.markdown, font: bodyFont,
                                                             alignment: .center)

        // The notch aside. It is READING copy about the app you just installed —
        // where to look for the flag — so it belongs to the content band, set as a
        // quiet footnote under the body with `related` air above it, not jammed
        // against the body at 6pt the way it used to be (it read as a sixth bullet
        // that had lost its dot, and its descenders all but touched the line above).
        // The what's-new variant does not show it at all: someone reading a change
        // log has been running the app for weeks and has already found the flag.
        var hint: NSTextField?
        if WelcomeContent.showsNotchHint(variant: variant) {
            let label = ReadingLabel.wrapping(font: .systemFont(ofSize: 11))
            label.stringValue = L10n.string(.welcomeHint)
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            hint = label
        }

        // MARK: setup band — section header + caption, the three toggles, status slot

        // Uppercase, tracked, secondary — the badge's typography without the badge's
        // tint, which is what makes it read as a section header rather than as a
        // second category pill. The parenthetical it used to carry
        // ("Your setup (reflects current settings)") is gone from the header and is
        // now the caption below it: the label carries the pattern, the caption
        // carries the explanation, exactly as the app's menu rows do.
        let setupHeader = sectionHeader(L10n.string(.welcomeSetupHeader))
        let setupCaption = NSTextField(labelWithString: L10n.string(.welcomeSetupCaption))
        setupCaption.font = .systemFont(ofSize: 10)
        setupCaption.textColor = .secondaryLabelColor
        // So pre-checked boxes below (Launch at Login already on, say) read as
        // reported status and not as something this window just did on its own.
        let setupHeaderBlock = NSStackView(views: [setupHeader, setupCaption])
        setupHeaderBlock.orientation = .vertical
        setupHeaderBlock.alignment = .leading
        setupHeaderBlock.spacing = Space.bound

        // The notify caption, indented to sit under the checkbox's LABEL rather
        // than under its square, and `bound` (4) below its own row while the rows
        // themselves are `group` (8) apart — so proximity alone answers "which
        // checkbox is this about". Only this row gets a caption: reserving caption
        // space under all three would be two permanently blank slots, which is the
        // exact "hole" pattern two earlier reviews of this window flagged.
        let notifyCaption = NSTextField(labelWithString: L10n.string(.welcomeNotifyCaption))
        notifyCaption.font = .systemFont(ofSize: 10)
        notifyCaption.textColor = .secondaryLabelColor
        notifyCaption.preferredMaxLayoutWidth = contentWidth - checkboxTextIndent
        let notifyCaptionRow = indented(notifyCaption)

        // A plain NSButton so the notify-hint case can be clickable (it opens
        // System Settings); the error case simply never fires its action. Text is
        // left-aligned because NSButton centres its title regardless of the
        // button's frame, which would leave the line floating on the window's axis
        // instead of lining up under the caption above it.
        controls.status.bezelStyle = .inline
        controls.status.isBordered = false
        controls.status.font = .systemFont(ofSize: 10)
        (controls.status.cell as? NSButtonCell)?.wraps = true
        (controls.status.cell as? NSButtonCell)?.lineBreakMode = .byWordWrapping
        (controls.status.cell as? NSButtonCell)?.alignment = .left
        // BOTH axes pinned to a constant, never merely capped: a width that varies
        // with content is as capable of moving things around as a height is —
        // NSStackView sizes a leading-aligned container to its widest row, so a
        // slot that shrank to nothing while empty and grew wide once populated
        // used to drag every checkbox's left edge sideways.
        controls.status.heightAnchor.constraint(equalToConstant: reservedStatusLineHeight).isActive = true
        controls.status.widthAnchor.constraint(
            equalToConstant: contentWidth - checkboxTextIndent).isActive = true

        // The status slot is the group's last row, not a floating band under it: it
        // always speaks about one of the three checkboxes, it shares their caption
        // column, and keeping it inside means its permanently-reserved 24pt reads as
        // the rows column running on rather than as a hole between two sections.
        let statusRow = indented(controls.status)
        let checkboxStack = NSStackView(views: [controls.launchAtLogin, controls.applications,
                                                controls.notify, notifyCaptionRow, statusRow])
        checkboxStack.orientation = .vertical
        checkboxStack.alignment = .leading
        checkboxStack.spacing = Space.group
        checkboxStack.setCustomSpacing(Space.bound, after: controls.notify)
        checkboxStack.setCustomSpacing(Space.bound, after: notifyCaptionRow)

        let setupSection = NSStackView(views: [setupHeaderBlock, checkboxStack])
        setupSection.orientation = .vertical
        setupSection.alignment = .leading
        setupSection.spacing = Space.related
        // Explicit fixed width rather than relying on some child happening to be
        // this wide: the section's leading edge must stay put regardless of what
        // is inside it, and a child's width is not a dependable way to promise that.
        setupSection.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        // MARK: footer band — privacy note + Done, one group

        let privacy = ReadingLabel.wrapping(font: .systemFont(ofSize: 10))
        privacy.stringValue = L10n.string(.welcomePrivacy)
        privacy.textColor = .secondaryLabelColor
        privacy.alignment = .center

        // MARK: the stack

        let contentSeparator = separator()
        let footerSeparator = separator()

        let views: [NSView] = [icon, badge, heading, body] + (hint.map { [$0] } ?? [])
            + [contentSeparator, setupSection, footerSeparator, privacy, controls.done]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Space.related
        stack.edgeInsets = NSEdgeInsets(top: Space.section, left: Space.margin,
                                        bottom: Space.margin, right: Space.margin)
        stack.setCustomSpacing(Space.group, after: icon)   // reclaim space the icon does not need
        stack.setCustomSpacing(badgeGap, after: badge)
        stack.setCustomSpacing(Space.bound, after: heading)
        // The band rule gets `section` on both sides, whichever view precedes it.
        stack.setCustomSpacing(Space.section, after: hint ?? body)
        stack.setCustomSpacing(Space.section, after: contentSeparator)
        stack.setCustomSpacing(Space.section, after: setupSection)
        stack.setCustomSpacing(Space.section, after: footerSeparator)
        stack.setCustomSpacing(Space.related, after: privacy)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for label in [heading, body, privacy] + (hint.map { [$0] } ?? []) {
            label.preferredMaxLayoutWidth = contentWidth
        }
        // Reading copy must never be squeezed to make something else fit. The
        // window's own size only "stays put" at priority 500 (AppKit's
        // NSLayoutPriorityWindowSizeStayPut), so anything above that pushes the
        // window taller instead of eating a line — and the controller then sizes
        // the window from `contentHeight` outright rather than leaving it to that
        // negotiation. Belt and braces, because a clipped last line is silent.
        for view in ([heading, body, privacy, hint] as [NSView?]).compactMap({ $0 }) {
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        stack.setClippingResistancePriority(.required, for: .vertical)

        return Assembly(stack: stack, icon: icon, badge: badge, heading: heading, body: body,
                        hint: hint, setupSection: setupSection,
                        setupHeader: setupHeader, setupCaption: setupCaption,
                        checkboxes: [controls.launchAtLogin, controls.applications, controls.notify],
                        notifyCaption: notifyCaption, statusSlot: controls.status,
                        privacy: privacy, doneButton: controls.done,
                        separators: [contentSeparator, footerSeparator])
    }

    // MARK: - pieces

    /// A band rule: full content width, exactly `separatorThickness` tall, filled
    /// with the system's dynamic separator colour so it lands correctly in both
    /// appearances. A custom box rather than `boxType = .separator` — see
    /// `separatorThickness` for why that one cannot be a hairline.
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.fillColor = .separatorColor
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: contentWidth),
            box.heightAnchor.constraint(equalToConstant: separatorThickness),
        ])
        return box
    }

    /// The window's one section-header treatment: uppercase, tracked and secondary
    /// at 11pt semibold. Uppercasing is `localizedUppercase` and happens in the
    /// view, never in the strings file — the same split `BadgePill` makes, so
    /// translators keep a readable string and the uppercasing stays locale-aware.
    /// The tracking ratio is `BadgePill.kernRatio` itself rather than a second
    /// copy of the number: uppercase text set solid is harder to read, and these
    /// two are the only places in the app that set any.
    static func sectionHeader(_ text: String) -> NSTextField {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let label = NSTextField(labelWithAttributedString: NSAttributedString(
            string: text.localizedUppercase,
            attributes: [.font: font,
                         .kern: font.pointSize * BadgePill.kernRatio,
                         // Explicit: an attributed string ignores the field's own
                         // textColor, which would leave this black-on-black in dark mode.
                         .foregroundColor: NSColor.secondaryLabelColor]))
        return label
    }

    /// Wraps `view` in a row that starts at the checkbox-label indent, so captions
    /// and the status slot share one left edge with the checkbox titles above them.
    static func indented(_ view: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: checkboxTextIndent).isActive = true
        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 0
        return row
    }
}
