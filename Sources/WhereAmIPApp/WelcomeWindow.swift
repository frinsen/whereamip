import AppKit
import ServiceManagement
import WhereAmIPCore

/// Welcome window: shown once on first launch, and again on a
/// maintainer-bumped `welcomeMilestone` (see `shouldShowWelcome(stored:)` in
/// WhereAmIPCore, gated by `Settings.welcomedMilestone`), or any time from
/// Settings ▸ Show Welcome Window. Explains what the app does, where to find
/// it, and offers the three most useful first-run toggles. Plain AppKit —
/// NSWindow + programmatic NSStackView layout, no xibs/SwiftUI — consistent
/// with the rest of the UI layer (MenuBuilder etc).
///
/// The only system prompt this window can ever trigger is the notification
/// permission dialog, and only as a direct result of the user checking that
/// one checkbox — never automatically. No other network call or permission
/// request happens here.
final class WelcomeWindowController: NSWindowController {
    private let settings: Settings
    private var launchAtLoginCheckbox: NSButton!
    private var applicationsCheckbox: NSButton!
    private var notifyCheckbox: NSButton!

    // The applications-link error and the notifications-denied hint used to
    // be two separate reserved slots stacked on top of each other. Almost
    // every real session has BOTH empty, so that was two ghost slots' worth
    // of ~always-blank space — exactly the "hole" a design review flagged.
    // They're now ONE shared slot (mergedStatusView) with a defined
    // precedence: an applications error, when present, always wins over the
    // notify hint (errors outrank hints); the notify hint reappears on its
    // own the moment the error clears, since renderMergedStatus() re-derives
    // the slot's content from both flags on every change to either.
    private var mergedStatusView: NSButton!
    private var applicationsErrorText: String? { didSet { renderMergedStatus() } }
    private var notifyHintActive = false { didSet { renderMergedStatus() } }

    // Fixed height for the shared conditionally-populated status slot
    // (mergedStatusView) — EXACTLY two lines at its 10pt font
    // (NSLayoutManager.defaultLineHeight(for: .systemFont(ofSize: 10))
    // measures 12pt/line, so 2 lines = 24pt; not a rounder but looser guess —
    // a looser reservation is exactly what read as a "hole" in the second
    // design review). The view stays permanently in the stack at this
    // height; only its text/tint/enabled state changes (never `.isHidden`,
    // never inserted/removed), so the window's size never jumps depending on
    // whether an error or a permission hint happens to be showing right now
    // (field-reported bug — see toggleApplications()/toggleNotify()).
    //
    // Height alone isn't enough, though: a *width* that varies with content
    // is just as capable of moving things around. NSStackView sizes a
    // leading-aligned container (setupSection/checkboxStack) to its widest
    // row; a capped-not-fixed width let a conditionally-populated view shrink
    // to near-zero while empty and grow wide once populated, which changed
    // checkboxStack's own intrinsic width and shifted its centered parent
    // (setupSection) sideways, dragging every checkbox's *left* edge with it
    // (a horizontal jump, reported after an earlier vertical-only fix). So
    // this view gets BOTH dimensions pinned to a constant — never just
    // capped — and setupSection ALSO gets an explicit fixed width (see
    // buildContent) so its own leading edge no longer depends on which of
    // its children happens to be widest.
    private static let reservedStatusLineHeight: CGFloat = 24
    // The one standard gap after a reserved status slot — replaces what was
    // an oversized, inconsistent custom-spacing value that (on top of the
    // reservation itself) made the setup→commit transition read as an empty
    // hole rather than a deliberate section break.
    private static let sectionGap: CGFloat = 20
    // Footer gaps (privacy→Done, Done→window-bottom-edge) are equalized to
    // this value rather than sectionGap: the side margins are 24pt, and the
    // bottom margin must never be smaller than the side margins, so the
    // footer's "standard" gap is pinned to match the sides exactly instead
    // of the plain ~20pt used elsewhere.
    private static let footerGap: CGFloat = 24
    // Approximates the leading edge of a standard AppKit checkbox's title
    // text (checkbox glyph + its gap before the label) — not pixel-exact
    // across every rendering, but close enough to visually align a caption
    // under the checkbox's *label*, not its square.
    private static let checkboxTextIndent: CGFloat = 19

    init(settings: Settings) {
        self.settings = settings
        // First run (never acknowledged anything yet) gets the plain welcome
        // copy; a milestone re-trigger (welcomedMilestone non-empty, but
        // older than the current welcomeMilestone) gets "what's new" framing
        // instead — same body/toggles either way, just the in-content
        // heading differs. The window's own titlebar title stays a plain
        // "WhereAmIP" (see buildContent) so the version isn't shown twice.
        let isFirstRun = settings.welcomedMilestone.isEmpty
        let headingText = isFirstRun
            ? "Welcome to WhereAmIP v\(whereamipVersion)"
            : "WhereAmIP v\(whereamipVersion) — what's new"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            // No .resizable — this is a small fixed-size informational window.
            // The actual height is whatever the content's Auto Layout fitting
            // size resolves to (see stack's `<=` bottom constraint below);
            // this is just the initial frame before that first layout pass.
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        // Plain, not the versioned heading text: avoids showing "Welcome to
        // WhereAmIP vX" twice (titlebar + in-content heading, ~240px apart).
        window.title = "WhereAmIP"
        // Close-only dialog: no miniaturize (nothing to restore to), no zoom
        // (layout is fixed-size, stretching it would just break it). The
        // style mask already omits .resizable/.miniaturizable, but the
        // standard title-bar buttons still exist as objects regardless —
        // explicitly disable them so there's no dead/misleading affordance.
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        // Closing (red button / Esc) should not deallocate the window/controller
        // out from under us before `done()` (Done button) has a chance to run,
        // and callers may re-show it — keep it alive for the app's lifetime.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(headingText: headingText)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildContent(headingText: String) {
        guard let window else { return }

        let iconView: NSView
        if let icon = NSApp.applicationIconImage {
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            // 64pt reads as "app identity" without the splash-screen feel a
            // bigger mark would have for a utility whose whole on-screen
            // identity is otherwise a 16pt menu bar flag.
            imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            iconView = imageView
        } else {
            // Fallback for environments with no app icon resolved (e.g. running
            // straight from `swift build` outside a .app bundle) — a flag emoji
            // stands in so the window never shows a blank icon area.
            let label = NSTextField(labelWithString: "🏳️")
            label.font = .systemFont(ofSize: 40)
            iconView = label
        }

        let heading = NSTextField(labelWithString: headingText)
        heading.font = .boldSystemFont(ofSize: 15)
        heading.alignment = .center

        let body = NSTextField(wrappingLabelWithString:
            "WhereAmIP lives in your menu bar and shows the country flag of your real internet " +
            "exit. The flag flips the moment a VPN takes over your default route, and warns you " +
            "about IPv6 leaks and connections that claim to be online but aren't.")
        body.alignment = .center
        body.font = .systemFont(ofSize: 12)

        let hint = NSTextField(wrappingLabelWithString:
            "Can't see the flag? A crowded menu bar may hide it behind the notch.")
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        // MARK: setup band — header + the three live-state toggles

        let setupHeader = NSTextField(labelWithString: "Your setup")
        setupHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        let setupHeaderCaption = NSTextField(labelWithString: "(reflects current settings)")
        setupHeaderCaption.font = .systemFont(ofSize: 10)
        setupHeaderCaption.textColor = .secondaryLabelColor
        // So pre-checked boxes below (e.g. Launch at Login already on) read
        // as reported status, not as something this window just did.
        let setupHeaderRow = NSStackView(views: [setupHeader, setupHeaderCaption])
        setupHeaderRow.orientation = .horizontal
        setupHeaderRow.alignment = .firstBaseline
        setupHeaderRow.spacing = 4

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login",
                                          target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        applicationsCheckbox = NSButton(checkboxWithTitle: "Add to Applications folder",
                                         target: self, action: #selector(toggleApplications))
        applicationsCheckbox.state = ApplicationsLink.isLinked() ? .on : .off

        // "Show Notifications" (not "Notify on exit/connectivity changes") —
        // a verb phrase like its siblings (Launch at Login, Add to
        // Applications folder, Check for Updates), matching System Settings'
        // "Notifications" vocabulary for the noun itself; the detail moves
        // to the caption below instead of living in the checkbox label.
        notifyCheckbox = NSButton(checkboxWithTitle: "Show Notifications",
                                   target: self, action: #selector(toggleNotify))
        // Never pre-checked, regardless of the actual current setting — the
        // system permission dialog may only ever appear as a *direct* result
        // of the user clicking this checkbox (or the Settings menu toggle),
        // never just from this window opening. On the launches where this
        // window shows (first run / milestone re-trigger), notifications
        // default to off anyway, so this rarely disagrees with reality.
        notifyCheckbox.state = .off

        // Single-line (not wrapping) label, so it must fit the caption's
        // available width (372 - checkboxTextIndent = 353pt) at this 10pt
        // font without truncating — measured directly via
        // NSString.size(withAttributes:) rather than eyeballed; the design
        // review's own suggested one-liner ("Alerts when your exit, route,
        // or connectivity changes. Asks for macOS permission when enabled.",
        // 465pt) and its proposed fallback (410pt) both overflowed, so this
        // is trimmed further (341pt) to actually fit.
        let notifyCaption = NSTextField(labelWithString: "Alerts on exit, route, or connectivity changes. Asks macOS permission.")
        notifyCaption.font = .systemFont(ofSize: 10)
        notifyCaption.textColor = .secondaryLabelColor
        notifyCaption.preferredMaxLayoutWidth = 372 - Self.checkboxTextIndent

        // Caption indented to align under the checkbox's *label* text, not
        // its square. The shared status slot (mergedStatusView, built below
        // as a sibling of setupSection) reuses this same checkboxTextIndent
        // so both lines share one left edge, even though the slot itself no
        // longer lives inside this row — see buildContent's assembly.
        let notifyIndentSpacer = NSView()
        notifyIndentSpacer.widthAnchor.constraint(equalToConstant: Self.checkboxTextIndent).isActive = true
        let notifyCaptionRow = NSStackView(views: [notifyIndentSpacer, notifyCaption])
        notifyCaptionRow.orientation = .horizontal
        notifyCaptionRow.alignment = .top
        notifyCaptionRow.spacing = 0

        let checkboxStack = NSStackView(views: [launchAtLoginCheckbox, applicationsCheckbox,
                                                 notifyCheckbox, notifyCaptionRow])
        checkboxStack.orientation = .vertical
        checkboxStack.alignment = .leading
        checkboxStack.spacing = 6
        checkboxStack.setCustomSpacing(2, after: notifyCheckbox)

        let setupSection = NSStackView(views: [setupHeaderRow, checkboxStack])
        setupSection.orientation = .vertical
        setupSection.alignment = .leading
        setupSection.spacing = 8
        // Explicit fixed width (== the stack's full usable content width, see
        // below) rather than relying on some child happening to be that
        // wide: setupSection's leading edge must stay put regardless of
        // what's inside it, and an internal child's width is not a
        // dependable way to guarantee that (see reservedStatusLineHeight doc).
        setupSection.widthAnchor.constraint(equalToConstant: 372).isActive = true

        // Shared conditional-status slot (applications-link error OR the
        // notifications-denied hint — see the class-level doc above for the
        // precedence rule). A plain NSButton so the notify-hint case can be
        // clickable (opens System Settings); the error case just never fires
        // its action (see openNotificationSettings()). Positioned as a
        // sibling right after setupSection, indented to the same left edge
        // as notifyCaption via its own spacer+fixed-width pairing below —
        // the "directly under the setup section" placement from the design
        // review, not nested inside checkboxStack.
        mergedStatusView = NSButton(title: "", target: self, action: #selector(openNotificationSettings))
        mergedStatusView.bezelStyle = .inline
        mergedStatusView.isBordered = false
        mergedStatusView.font = .systemFont(ofSize: 10)
        (mergedStatusView.cell as? NSButtonCell)?.wraps = true
        (mergedStatusView.cell as? NSButtonCell)?.lineBreakMode = .byWordWrapping
        // NSButton centers its title by default regardless of the button's
        // own frame alignment; left-align the text itself so it lines up
        // with notifyCaption above it instead of floating on the window's axis.
        (mergedStatusView.cell as? NSButtonCell)?.alignment = .left
        let statusIndentSpacer = NSView()
        statusIndentSpacer.widthAnchor.constraint(equalToConstant: Self.checkboxTextIndent).isActive = true
        let statusRow = NSStackView(views: [statusIndentSpacer, mergedStatusView])
        statusRow.orientation = .horizontal
        statusRow.alignment = .top
        statusRow.spacing = 0

        // MARK: commit band — privacy note + Done

        let privacy = NSTextField(wrappingLabelWithString: "No tracking, no history, no logs.")
        privacy.font = .systemFont(ofSize: 10)
        privacy.textColor = .secondaryLabelColor
        privacy.alignment = .center

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"   // Return triggers Done
        // Belt-and-suspenders for the filled/blue default-button look on top
        // of the Return keyEquivalent above — the one thing this one-shot
        // dialog must get right is answering "what do I do now".
        window.defaultButtonCell = doneButton.cell as? NSButtonCell

        // MARK: assembly — three bands: pitch / setup / commit

        let stack = NSStackView(views: [iconView, heading, body, hint,
                                         setupSection, statusRow,
                                         privacy, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        // Bottom inset equals the side insets (24) — never smaller, per the
        // footer fix: Done→window-bottom-edge is a real margin, not a
        // between-elements gap, so it follows footerGap, not sectionGap.
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: Self.footerGap, right: 24)
        stack.setCustomSpacing(8, after: iconView)     // reclaim space the icon doesn't need
        stack.setCustomSpacing(4, after: heading)
        stack.setCustomSpacing(6, after: body)          // tighten hint-to-body: one thought
        stack.setCustomSpacing(24, after: hint)         // air above the checkbox group: pitch → setup
        stack.setCustomSpacing(4, after: setupSection)  // status slot stays visually part of setup
        stack.setCustomSpacing(Self.sectionGap, after: statusRow) // setup → commit
        stack.setCustomSpacing(Self.footerGap, after: privacy) // privacy → Done, equal to Done → bottom edge
        stack.translatesAutoresizingMaskIntoConstraints = false

        [heading, body, hint, privacy].forEach {
            $0.preferredMaxLayoutWidth = 372   // 420 window width - 24*2 edge insets
        }
        // Both axes pinned to a CONSTANT (not a ceiling) — see the
        // reservedStatusLineHeight doc above for why a `<=` width still let
        // the checkbox group jump.
        mergedStatusView.heightAnchor.constraint(equalToConstant: Self.reservedStatusLineHeight).isActive = true
        mergedStatusView.widthAnchor.constraint(equalToConstant: 372 - Self.checkboxTextIndent).isActive = true
        // Starts empty/cleared — see renderMergedStatus(), driven by the two
        // didSet-observed flags above, both false/nil at construction time.

        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Best-effort, same convention as the menu's toggle — SMAppService
            // failures here aren't actionable from a first-run window; just
            // resync the checkbox below to whatever actually happened.
        }
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleApplications() {
        // NSButton has already flipped its own state by the time the action
        // fires, so `.state == .on` reflects the user's requested new state.
        let turningOn = applicationsCheckbox.state == .on
        do {
            try ApplicationsLink.setLinked(turningOn, bundlePath: Bundle.main.bundlePath)
            // Clearing this is what lets the notify hint (if any) reappear —
            // see renderMergedStatus()'s precedence rule.
            applicationsErrorText = nil
        } catch {
            applicationsErrorText = "\(error)"
            // Revert the checkbox to actual on-disk truth rather than trusting
            // the click — the operation didn't happen.
            applicationsCheckbox.state = ApplicationsLink.isLinked() ? .on : .off
        }
    }

    @objc private func toggleNotify() {
        // NSButton has already flipped its own state by the time the action
        // fires, so `.state == .on` reflects the user's requested new state.
        guard notifyCheckbox.state == .on else {
            settings.notificationsEnabled = false
            notifyHintActive = false
            return
        }
        NotificationPermissionFlow.requestEnable { [weak self] granted, needsSystemSettings in
            guard let self else { return }
            if needsSystemSettings {
                self.notifyCheckbox.state = .off
                self.notifyHintActive = true
            } else {
                self.settings.notificationsEnabled = granted
                self.notifyCheckbox.state = granted ? .on : .off
                self.notifyHintActive = false
            }
        }
    }

    // Single source of truth for the shared status slot's content —
    // called from both didSet observers above, so the slot always reflects
    // whichever flag is authoritative right now. An applications error, if
    // present, always wins (errors outrank hints); with no error, the
    // notify hint shows if active; otherwise the slot is genuinely empty.
    // Text/tint/enabled only — mergedStatusView never leaves the stack and
    // is never `.isHidden`, so re-rendering it can't change the window's
    // layout (both axes are pinned to a constant — see
    // reservedStatusLineHeight doc).
    private func renderMergedStatus() {
        if let error = applicationsErrorText {
            mergedStatusView.title = error
            mergedStatusView.contentTintColor = .systemRed
        } else if notifyHintActive {
            mergedStatusView.title = "Notifications are disabled in System Settings — open Notifications settings"
            mergedStatusView.contentTintColor = .linkColor
        } else {
            mergedStatusView.title = ""
        }
    }

    @objc private func openNotificationSettings() {
        // mergedStatusView stays enabled at all times (so its text never
        // dims/grays the way a disabled NSButton's does — the applications
        // error needs to read as plain, full-color text, not a grayed-out
        // control) — so this action can fire from a click landing on the
        // slot while it's showing an error or is empty. Only actually open
        // System Settings when the slot is genuinely showing the notify hint.
        guard applicationsErrorText == nil, notifyHintActive else { return }
        NotificationPermissionFlow.openSystemSettings()
    }

    @objc private func done() {
        // Only Done acknowledges the current milestone — see the comment at
        // the call site in AppDelegate for why closing any other way must
        // not. On a manually-reopened window (Settings ▸ Show Welcome
        // Window) this just re-stores the same value; harmless.
        settings.welcomedMilestone = welcomeMilestone
        close()
    }

    func show() {
        // LSUIElement (accessory) apps aren't automatically brought frontmost
        // when a window is shown — without this the welcome window can open
        // behind other apps, or without key focus, on first launch.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
