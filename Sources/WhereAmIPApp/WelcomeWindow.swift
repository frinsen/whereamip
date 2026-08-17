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

    init(settings: Settings) {
        self.settings = settings
        // First run (never acknowledged anything yet) gets the plain welcome
        // copy; a milestone re-trigger (welcomedMilestone non-empty, but
        // older than the current welcomeMilestone) gets "what's new" framing
        // instead — same body/toggles either way, just the headline differs.
        let isFirstRun = settings.welcomedMilestone.isEmpty
        let titleText = isFirstRun
            ? "Welcome to WhereAmIP v\(whereamipVersion)"
            : "WhereAmIP v\(whereamipVersion) — what's new"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            // No .resizable — this is a small fixed-size informational window.
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = titleText
        // Closing (red button / Esc) should not deallocate the window/controller
        // out from under us before `done()` (Done button) has a chance to run,
        // and callers may re-show it — keep it alive for the app's lifetime.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(titleText: titleText)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildContent(titleText: String) {
        guard let window else { return }

        let iconView: NSView
        if let icon = NSApp.applicationIconImage {
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            iconView = imageView
        } else {
            // Fallback for environments with no app icon resolved (e.g. running
            // straight from `swift build` outside a .app bundle) — a flag emoji
            // stands in so the window never shows a blank icon area.
            let label = NSTextField(labelWithString: "🏳️")
            label.font = .systemFont(ofSize: 44)
            iconView = label
        }

        let title = NSTextField(labelWithString: titleText)
        title.font = .boldSystemFont(ofSize: 15)
        title.alignment = .center

        let body = NSTextField(wrappingLabelWithString:
            "WhereAmIP lives in your menu bar and shows the country flag of your real internet " +
            "exit. The flag flips the moment a VPN takes over your default route, and warns you " +
            "about IPv6 leaks and connections that look up but are actually dead.")
        body.alignment = .center
        body.font = .systemFont(ofSize: 12)

        let hint = NSTextField(wrappingLabelWithString:
            "Look for the flag in your menu bar — on notched MacBooks a crowded menu bar can " +
            "hide it behind the notch.")
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login",
                                          target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off

        applicationsCheckbox = NSButton(checkboxWithTitle: "Show in Applications",
                                         target: self, action: #selector(toggleApplications))
        applicationsCheckbox.state = ApplicationsLink.isLinked() ? .on : .off

        applicationsErrorLabel = NSTextField(wrappingLabelWithString: "")
        applicationsErrorLabel.font = .systemFont(ofSize: 10)
        applicationsErrorLabel.textColor = .systemRed
        applicationsErrorLabel.isHidden = true

        notifyCheckbox = NSButton(checkboxWithTitle: "Notify on exit/connectivity changes",
                                   target: self, action: #selector(toggleNotify))
        // Never pre-checked, regardless of the actual current setting — the
        // system permission dialog may only ever appear as a *direct* result
        // of the user clicking this checkbox (or the Settings menu toggle),
        // never just from this window opening. On the launches where this
        // window shows (first run / milestone re-trigger), notifications
        // default to off anyway, so this rarely disagrees with reality.
        notifyCheckbox.state = .off

        let notifySubLabel = NSTextField(labelWithString: "(asks for macOS permission when enabled)")
        notifySubLabel.font = .systemFont(ofSize: 10)
        notifySubLabel.textColor = .secondaryLabelColor

        notifyHintButton = NSButton(title: "Notifications are disabled in System Settings — open Notifications settings",
                                     target: self, action: #selector(openNotificationSettings))
        notifyHintButton.bezelStyle = .inline
        notifyHintButton.isBordered = false
        notifyHintButton.contentTintColor = .linkColor
        notifyHintButton.font = .systemFont(ofSize: 10)
        notifyHintButton.isHidden = true

        let privacy = NSTextField(wrappingLabelWithString:
            "No tracking, no history, no logs — see the README's Privacy section.")
        privacy.font = .systemFont(ofSize: 10)
        privacy.textColor = .secondaryLabelColor
        privacy.alignment = .center

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"   // default button

        let checkboxStack = NSStackView(views: [launchAtLoginCheckbox, applicationsCheckbox,
                                                 notifyCheckbox, notifySubLabel, notifyHintButton])
        checkboxStack.orientation = .vertical
        checkboxStack.alignment = .leading
        checkboxStack.spacing = 6
        checkboxStack.setCustomSpacing(2, after: notifyCheckbox)

        let stack = NSStackView(views: [iconView, title, body, hint, checkboxStack, applicationsErrorLabel, privacy, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(20, after: hint)
        stack.translatesAutoresizingMaskIntoConstraints = false

        [title, body, hint, applicationsErrorLabel, privacy, notifySubLabel].forEach {
            $0.preferredMaxLayoutWidth = 372   // 420 window width - 24*2 edge insets
        }
        notifyHintButton.widthAnchor.constraint(lessThanOrEqualToConstant: 372).isActive = true

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
            applicationsErrorLabel.isHidden = true
            applicationsErrorLabel.stringValue = ""
        } catch {
            applicationsErrorLabel.stringValue = "\(error)"
            applicationsErrorLabel.isHidden = false
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
            notifyHintButton.isHidden = true
            return
        }
        NotificationPermissionFlow.requestEnable { [weak self] granted, needsSystemSettings in
            guard let self else { return }
            if needsSystemSettings {
                self.notifyCheckbox.state = .off
                self.notifyHintButton.isHidden = false
            } else {
                self.settings.notificationsEnabled = granted
                self.notifyCheckbox.state = granted ? .on : .off
                self.notifyHintButton.isHidden = true
            }
        }
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
