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
    private var applicationsErrorLabel: NSTextField!
    private var notifyCheckbox: NSButton!
    private var notifyHintButton: NSButton!

    // Fixed height for the two conditionally-populated status lines
    // (applicationsErrorLabel, notifyHintButton) — ~2 lines at their 10pt
    // font. Both views stay permanently in their stacks at this height;
    // only their text/enabled state changes (never `.isHidden`, never
    // inserted/removed), so the window's size never jumps depending on
    // whether an error or a permission hint happens to be showing right now
    // (field-reported bug — see toggleApplications()/toggleNotify()).
    //
    // Height alone isn't enough, though: a *width* that varies with content
    // is just as capable of moving things around. NSStackView sizes a
    // leading-aligned container (setupSection/checkboxStack) to its widest
    // row; when notifyHintButton's width was only capped (<=) rather than
    // fixed, it shrank to near-zero while empty and grew to ~350pt once
    // populated — that changed checkboxStack's own intrinsic width, which
    // shifted its centered parent (setupSection) sideways, dragging every
    // checkbox's *left* edge with it (a horizontal jump, reported after the
    // vertical one was fixed). So every conditionally-populated view in this
    // window gets BOTH dimensions pinned to a constant — never just capped —
    // so no sibling's layout can depend on this view's content at all.
    private static let reservedStatusLineHeight: CGFloat = 28
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            // No .resizable — this is a small fixed-size informational window.
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

        notifyCheckbox = NSButton(checkboxWithTitle: "Notify on exit/connectivity changes",
                                   target: self, action: #selector(toggleNotify))
        // Never pre-checked, regardless of the actual current setting — the
        // system permission dialog may only ever appear as a *direct* result
        // of the user clicking this checkbox (or the Settings menu toggle),
        // never just from this window opening. On the launches where this
        // window shows (first run / milestone re-trigger), notifications
        // default to off anyway, so this rarely disagrees with reality.
        notifyCheckbox.state = .off

        let notifyCaption = NSTextField(labelWithString: "Asks for macOS permission when enabled.")
        notifyCaption.font = .systemFont(ofSize: 10)
        notifyCaption.textColor = .secondaryLabelColor

        // Denied-permission hint: starts cleared/disabled (not hidden — see
        // reservedStatusLineHeight doc above). toggleNotify() only ever sets
        // .title/.isEnabled, never touches visibility or stack membership.
        notifyHintButton = NSButton(title: "", target: self, action: #selector(openNotificationSettings))
        notifyHintButton.bezelStyle = .inline
        notifyHintButton.isBordered = false
        notifyHintButton.contentTintColor = .linkColor
        notifyHintButton.font = .systemFont(ofSize: 10)
        notifyHintButton.isEnabled = false
        (notifyHintButton.cell as? NSButtonCell)?.wraps = true
        (notifyHintButton.cell as? NSButtonCell)?.lineBreakMode = .byWordWrapping

        // notifyCaption + notifyHintButton indented to align under the
        // checkbox's *label* text, not its square (item: caption placement).
        let notifyCaptionColumn = NSStackView(views: [notifyCaption, notifyHintButton])
        notifyCaptionColumn.orientation = .vertical
        notifyCaptionColumn.alignment = .leading
        notifyCaptionColumn.spacing = 2
        let notifyIndentSpacer = NSView()
        notifyIndentSpacer.widthAnchor.constraint(equalToConstant: Self.checkboxTextIndent).isActive = true
        let notifyCaptionRow = NSStackView(views: [notifyIndentSpacer, notifyCaptionColumn])
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

        // Applications-link error: same reserved-slot treatment as the
        // notify hint above — never hidden, only its text changes.
        applicationsErrorLabel = NSTextField(wrappingLabelWithString: "")
        applicationsErrorLabel.font = .systemFont(ofSize: 10)
        applicationsErrorLabel.textColor = .systemRed
        applicationsErrorLabel.maximumNumberOfLines = 2
        applicationsErrorLabel.cell?.truncatesLastVisibleLine = true

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
                                         setupSection, applicationsErrorLabel,
                                         privacy, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.setCustomSpacing(8, after: iconView)     // reclaim space the icon doesn't need
        stack.setCustomSpacing(4, after: heading)
        stack.setCustomSpacing(6, after: body)          // tighten hint-to-body: one thought
        stack.setCustomSpacing(24, after: hint)         // air above the checkbox group: pitch → setup
        stack.setCustomSpacing(6, after: setupSection)  // error status stays visually part of setup
        stack.setCustomSpacing(24, after: applicationsErrorLabel) // setup → commit
        stack.setCustomSpacing(18, after: privacy)      // extra air right above Done
        stack.translatesAutoresizingMaskIntoConstraints = false

        [heading, body, hint, applicationsErrorLabel, privacy].forEach {
            $0.preferredMaxLayoutWidth = 372   // 420 window width - 24*2 edge insets
        }
        notifyCaption.preferredMaxLayoutWidth = 372 - Self.checkboxTextIndent
        // Both axes pinned to a CONSTANT (not a ceiling) for every
        // conditionally-populated view — see the reservedStatusLineHeight
        // doc above for why a `<=` width still let the checkbox group jump.
        applicationsErrorLabel.heightAnchor.constraint(equalToConstant: Self.reservedStatusLineHeight).isActive = true
        applicationsErrorLabel.widthAnchor.constraint(equalToConstant: 372).isActive = true
        notifyHintButton.heightAnchor.constraint(equalToConstant: Self.reservedStatusLineHeight).isActive = true
        notifyHintButton.widthAnchor.constraint(equalToConstant: 372 - Self.checkboxTextIndent).isActive = true

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
            // Clear text only — the label itself stays in the stack at its
            // reserved height (see reservedStatusLineHeight), so the window
            // never resizes based on whether an error is showing.
            applicationsErrorLabel.stringValue = ""
        } catch {
            applicationsErrorLabel.stringValue = "\(error)"
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
            clearNotifyHint()
            return
        }
        NotificationPermissionFlow.requestEnable { [weak self] granted, needsSystemSettings in
            guard let self else { return }
            if needsSystemSettings {
                self.notifyCheckbox.state = .off
                self.notifyHintButton.title = "Notifications are disabled in System Settings — open Notifications settings"
                self.notifyHintButton.isEnabled = true
            } else {
                self.settings.notificationsEnabled = granted
                self.notifyCheckbox.state = granted ? .on : .off
                self.clearNotifyHint()
            }
        }
    }

    // Text/enabled only — see reservedStatusLineHeight doc: notifyHintButton
    // never leaves the stack and is never `.isHidden`, so clearing it can't
    // change the window's layout.
    private func clearNotifyHint() {
        notifyHintButton.title = ""
        notifyHintButton.isEnabled = false
    }

    @objc private func openNotificationSettings() {
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
