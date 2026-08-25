import AppKit
import ServiceManagement
import UserNotifications
import WhereAmIPCore
import WhereAmIPUI

/// Welcome window: shown once on first launch, and again on a
/// maintainer-bumped `welcomeMilestone` (see `shouldShowWelcome(stored:)` in
/// WhereAmIPCore, gated by `Settings.welcomedMilestone`), or any time from
/// Settings ▸ Show Welcome Window / What's New. Explains what the app does,
/// where to find it, and offers the three most useful first-run toggles.
/// Plain AppKit — NSWindow + programmatic NSStackView layout, no xibs/SwiftUI
/// — consistent with the rest of the UI layer (MenuBuilder etc).
///
/// One window, two variants (see `WelcomeContent.Variant`). The variant is fixed
/// at construction: the copy is rendered ONCE in `buildContent` so the window's
/// height settles before it is ever shown, so switching variants means a new
/// window, not a re-render — see AppDelegate's `showWelcome(variant:)`.
///
/// The only system prompt this window can ever trigger is the notification
/// permission dialog, and only as a direct result of the user checking that
/// one checkbox — never automatically. No other network call or permission
/// request happens here.
final class WelcomeWindowController: NSWindowController {
    private let settings: Settings
    /// Which copy this window was built with. Read by AppDelegate to decide whether an
    /// already-open window can be re-focused or has to be replaced.
    let variant: WelcomeContent.Variant
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

    // Arrangement, spacing and size all live in WhereAmIPUI/WelcomeLayout —
    // including the shared status slot's pinned dimensions, which are what stop
    // the window jumping around when an error or a permission hint appears. This
    // controller keeps the window, the three live toggles and their actions;
    // it holds no geometry of its own.

    init(settings: Settings, variant: WelcomeContent.Variant) {
        self.settings = settings
        self.variant = variant
        // `.intro` is the "Getting Started" badge and the first-run pitch; `.whatsNew`
        // is the "What's New" badge and the milestone's bundled highlights (the
        // heading itself is now the same "WhereAmIP v%@" for both — only the version
        // filling it differs). WHICH one
        // is the caller's decision — the launch-time auto-show derives it from
        // history (WelcomeContent.variant(for:)), the two Settings entries name it
        // outright. Both the copy and that mapping live in WhereAmIPUI's
        // WelcomeContent (pure, unit-tested there); this window only lays out
        // whatever it hands back. The window's own titlebar title stays a plain
        // "WhereAmIP" (see buildContent) so the version isn't shown twice.
        let copy = WelcomeContent.copy(variant: variant)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeLayout.windowWidth, height: 360),
            // No .resizable — this is a small fixed-size informational window.
            // The height here is a placeholder: buildContent() replaces it with
            // the content's own resolved height before the window is shown.
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        // Plain, not the versioned heading text: avoids showing "WhereAmIP vX"
        // twice (titlebar + in-content heading, ~240px apart).
        window.title = L10n.string(.welcomeWindowTitle)
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
        buildContent(copy: copy)
        window.center()
        // Async, read-only correction on top of the synchronous
        // settings.notificationsEnabled guess above — see
        // refreshNotifyCheckboxFromTruth()'s doc for why this can't just
        // run synchronously during buildContent().
        refreshNotifyCheckboxFromTruth()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildContent(copy: WelcomeContent.Copy) {
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

        // MARK: the three live toggles — the only interactive content here

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L10n.string(.settingsLaunchAtLogin),
                                          target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        applicationsCheckbox = NSButton(checkboxWithTitle: L10n.string(.settingsApplicationsLink),
                                         target: self, action: #selector(toggleApplications))
        applicationsCheckbox.state = ApplicationsLink.isLinked() ? .on : .off

        // "Show Notifications" (not "Notify on exit/connectivity changes") —
        // a verb phrase like its siblings (Launch at Login, Add to
        // Applications folder, Check for Updates), matching System Settings'
        // "Notifications" vocabulary for the noun itself; the detail moves
        // to the caption below instead of living in the checkbox label.
        notifyCheckbox = NSButton(checkboxWithTitle: L10n.string(.settingsNotifications),
                                   target: self, action: #selector(toggleNotify))
        // Reflects live state, like its two siblings (Launch at Login, Add
        // to Applications folder) — NOT hardcoded off. Field bug: the
        // original "never pre-checked" rule was written for first-run only,
        // where notificationsEnabled is always false anyway, so it silently
        // disagreed with reality the moment this window could be reopened
        // later (Settings ▸ Show Welcome Window) with the setting already
        // on — screenshot showed Settings ✓ checked, welcome window
        // unchecked, right under a header whose caption claims it reflects
        // current settings. Refined further once the real system
        // authorization is known — see refreshNotifyCheckboxFromTruth(),
        // called from init() after buildContent() returns.
        notifyCheckbox.state = settings.notificationsEnabled ? .on : .off

        // Shared conditional-status slot (applications-link error OR the
        // notifications-denied hint — see the class-level doc above for the
        // precedence rule). A plain NSButton so the notify-hint case can be
        // clickable (opens System Settings); the error case just never fires
        // its action (see openNotificationSettings()). Its appearance and its
        // pinned size are WelcomeLayout's; only the target/action is ours.
        mergedStatusView = NSButton(title: "", target: self, action: #selector(openNotificationSettings))

        let doneButton = NSButton(title: L10n.string(.welcomeDone), target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"   // Return triggers Done
        // Belt-and-suspenders for the filled/blue default-button look on top
        // of the Return keyEquivalent above — the one thing this one-shot
        // dialog must get right is answering "what do I do now".
        window.defaultButtonCell = doneButton.cell as? NSButtonCell

        // MARK: everything else — arrangement, spacing and size live in WelcomeLayout

        let layout = WelcomeLayout.build(
            variant: variant, copy: copy, icon: iconView,
            controls: WelcomeLayout.Controls(launchAtLogin: launchAtLoginCheckbox,
                                             applications: applicationsCheckbox,
                                             notify: notifyCheckbox,
                                             status: mergedStatusView,
                                             done: doneButton))
        // Starts empty/cleared — see renderMergedStatus(), driven by the two
        // didSet-observed flags above, both false/nil at construction time.

        let stack = layout.stack
        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
        // Sized ONCE, here, from the content's own resolved height — not left to
        // AppKit's window-size negotiation, where the window's current size holds
        // at priority 500 and anything above it merely *tends* to win. That
        // negotiation is what makes a too-long body silently lose its last line
        // instead of opening a taller window, and a clipped last line is a bug
        // nobody sees until a release note grows. The window never resizes again:
        // the copy is rendered before this call and nothing re-renders it.
        window.setContentSize(layout.contentSize)
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

    // Corrects the checkbox's synchronous settings.notificationsEnabled
    // guess (set in buildContent()) against the *real* OS-level
    // authorization, once known. Deliberately calls
    // `UNUserNotificationCenter.getNotificationSettings` directly rather
    // than going through `NotificationPermissionFlow.requestEnable` — that
    // helper's `.notDetermined` branch calls `requestAuthorization`, which
    // would pop the system permission dialog just from this window opening.
    // This only ever *reads* the current status; the invariant that the
    // dialog may only appear as a direct result of the user actively
    // checking the box from off (toggleNotify()) is unchanged.
    //
    // An enabled setting the OS has since denied is honestly "off": showing
    // it checked would just be a second copy of the exact bug this fixes
    // (Settings said on, reality said no) — so denied always wins, and also
    // surfaces the same denied-hint toggleNotify() shows on a live attempt,
    // via the shared status slot.
    private func refreshNotifyCheckboxFromTruth() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notifSettings in
            DispatchQueue.main.async {
                guard let self else { return }
                let denied = notifSettings.authorizationStatus == .denied
                self.notifyCheckbox.state = (self.settings.notificationsEnabled && !denied) ? .on : .off
                self.notifyHintActive = denied
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
            mergedStatusView.title = L10n.string(.welcomeNotifyHint)
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
        // not. Variant-blind by design (WelcomeContent.acknowledgedMilestone,
        // pinned by a test there): What's New marks the release seen exactly
        // as the auto-shown window does, and re-reading the pitch from
        // Settings ▸ Show Welcome Window just re-stores the same value.
        settings.welcomedMilestone = WelcomeContent.acknowledgedMilestone(for: variant)
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
