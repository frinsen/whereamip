import AppKit
import Network
import ServiceManagement
import UserNotifications
import WhereAmIPCore
import WhereAmIPUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var monitor: Monitor!
    var pathMonitor: NWPathMonitor!
    let settings = Settings()
    let updateChecker = UpdateChecker()
    var lastState = ExitState()
    var availableUpdate: String?
    var restartUpdate: String?
    private var lastDiskCheckAt: Date?
    // Build-once-per-open guard for the dropdown (see MenuTrackingSession): AppKit calls
    // menuNeedsUpdate on every keydown during tracking, ⌥ included.
    let menuSession = MenuTrackingSession()
    var welcomeWindowController: WelcomeWindowController?
    // Separate from the welcome window's controller on purpose — the two windows
    // are independent and may be open at the same time.
    var helpWindowController: HelpWindowController?
    // Proof-of-freshness for the dropdown's "Checked:" row — app-local only,
    // never touches ExitState/Codable/the JSON golden files. Set exclusively
    // by runMonitorRefresh() below, which every direct fullRefresh/probeTick
    // call site is routed through so none of them is missed.
    var lastChecked: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = NSMenu()
        statusItem.menu!.delegate = self

        // Shown once (and again on a maintainer-bumped welcomeMilestone —
        // see Version.swift), after the status item exists so the window can
        // point at something already on screen. Gated by shouldShowWelcome
        // (pure logic in Core, unit-tested there) — only Done stores
        // welcomedMilestone, so dismissing via the close button/Esc shows it
        // again next launch rather than losing it for good. Monitor setup
        // below runs regardless of this window; the app's core behavior
        // never waits on it.
        if shouldShowWelcome(stored: settings.welcomedMilestone) {
            welcomeWindowController = WelcomeWindowController(settings: settings)
            welcomeWindowController?.show()
        }

        monitor = Monitor(
            geo: GeoProviderChain(), probe: ConnectivityProbe(),
            route: AppRoute(), httpIP: HTTPIPFetcher(), stackIP: StackPinnedIP(),
            relayRanges: RelayRanges.bundled(),
            onChange: { [weak self] state in
                DispatchQueue.main.async { self?.stateChanged(state) }
            },
            onEvents: { [weak self] events in
                DispatchQueue.main.async { self?.eventsHappened(events) }
            })

        pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            // Not routed through runMonitorRefresh(): pathChanged() debounces
            // and calls fullRefresh() entirely *inside* the Monitor actor
            // after a delay, with no completion hook back out to here — this
            // one trigger's eventual refresh can't update lastChecked without
            // a Monitor API change, which is out of scope for an app-local
            // timestamp. Every trigger AppDelegate calls directly (below) is
            // covered.
            Task { await self.monitor.pathChanged() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "whereamip.path"))

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        Task { await self.runMonitorRefresh(full: true) }
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.runMonitorRefresh(full: false) }
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.runMonitorRefresh(full: true) }
        }
        // Cadence per spec: launch + once per 24h + on manual Refresh.
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    @objc func didWake() { Task { await self.runMonitorRefresh(full: true) } }

    /// One presentation rule for both auxiliary windows: if the one we already hold is still
    /// on screen, focus THAT rather than building a second one.
    ///
    /// Replacing the controller unconditionally looked harmless because the old window stays
    /// visible (`isReleasedWhenClosed = false`) — but only the window survives. Its controller
    /// is released the moment this property is overwritten, and AppKit holds `target` weakly,
    /// so every control on the orphan goes inert: the welcome window's Done button stops
    /// storing the milestone and stops closing, and the help window stops re-wrapping its text
    /// on resize. A dead-but-visible window is a worse outcome than either a fresh one or none.
    ///
    /// Returns the controller to store, so the caller's assignment stays a single expression.
    func present<C: AuxiliaryWindowController>(_ existing: C?, make: () -> C) -> C {
        if let existing, existing.window?.isVisible == true {
            existing.show()   // re-focus: activate + makeKeyAndOrderFront
            return existing
        }
        let fresh = make()
        fresh.show()
        return fresh
    }

    // Every direct fullRefresh/probeTick call site is routed through this one
    // helper so lastChecked (the dropdown's "Checked:" row) can never miss a
    // trigger — see the pathMonitor callback above for the one exception and
    // why it can't be covered here. @MainActor so the `lastChecked = Date()`
    // write below always lands back on the main thread after the `await`,
    // same as the existing `await MainActor.run { … }` pattern in
    // checkForUpdates() uses for its own post-await property write.
    @MainActor
    func runMonitorRefresh(full: Bool) async {
        if full {
            await monitor.fullRefresh()
        } else {
            await monitor.probeTick()
        }
        lastChecked = Date()
    }

    // Manual-refresh-only loading cue (spec §2 field lesson: "silent vs
    // manual refresh" — periodic/automatic triggers never emit a loading
    // state, only a user-initiated Refresh click does). Dims the status
    // button natively — the same `appearsDisabled` mechanism system menu
    // bar items use to show "busy" — rather than swapping its title/image.
    // An earlier version replaced the glyph with "…", which changed the
    // status item's WIDTH and made every neighboring menu bar icon visibly
    // shift left and back (field-reported jitter, same disease class as the
    // earlier welcome-window jumping bug); dimming changes zero geometry
    // and works identically across all three menu bar styles (emoji/code/
    // image) with no new per-style branching.
    func setManualRefreshIndicator(_ inProgress: Bool) {
        statusItem.button?.appearsDisabled = inProgress
    }

    // Passive check only — never downloads or applies anything, just learns
    // whether a newer GitHub release exists. Respects the `updates` setting:
    // when disabled, no network request is made at all.
    func checkForUpdates() {
        checkInstalledVersion()
        guard settings.updatesEnabled else { return }
        Task {
            let latest = await updateChecker.latestVersion()
            let newer = latest.map { SemVer.isNewer($0, than: whereamipVersion) } ?? false
            await MainActor.run { self.availableUpdate = newer ? latest : nil }
        }
    }

    // Detects "brew upgrade already replaced the files on disk, but this
    // process is still the old binary" by comparing the version installed at
    // the stable brew opt path against our own. Cheap (one plist read), but
    // still I/O — never call this from menuNeedsUpdate (menu-build must stay
    // I/O-free). Evaluated at the same cadence as the GitHub check (launch,
    // daily timer, manual Refresh) plus a throttled pass from stateChanged
    // below, since that's the only place likely to observe the change soon
    // after a background `brew upgrade` completes.
    func checkInstalledVersion() {
        guard let onDisk = InstalledVersion.onDisk(bundlePath: Bundle.main.bundlePath) else {
            restartUpdate = nil
            return
        }
        restartUpdate = SemVer.isNewer(onDisk.version, than: whereamipVersion) ? onDisk.version : nil
    }

    func stateChanged(_ state: ExitState) {
        lastState = state
        let (title, image) = StatusItemRenderer.render(state.glyph(style: settings.menuBarStyle),
                                                        warning: state.ipv6Leak || state.dns.leak == .confirmed)
        statusItem.button?.title = title ?? ""
        statusItem.button?.image = image

        // Throttled disk-version check (at most once/60s) — stateChanged fires
        // often (probe ticks, route changes), so this catches a `brew upgrade`
        // that finished in the background well before the next daily/manual
        // update check without adding I/O on every single state change.
        let now = Date()
        if lastDiskCheckAt == nil || now.timeIntervalSince(lastDiskCheckAt!) >= 60 {
            lastDiskCheckAt = now
            checkInstalledVersion()
        }
    }

    // Shared relaunch mechanism for both the update-restart row (which targets
    // the newer opt-path bundle) and the plain "Restart WhereAmIP" row (which
    // targets our own running bundle). `open -n` — rather than exec'ing the
    // binary directly — properly re-registers the new instance with Launch
    // Services. The new instance recreates its own status item, so a brief
    // moment with no (or two) menu bar icons during the switch is expected
    // and acceptable.
    //
    // Field bug (first real 0.3.2→0.4 upgrade): the previous version fired
    // `open -n <path>` immediately, then called `NSApp.terminate` after a
    // fixed 0.5s delay. That delay was a race, not a synchronization — when
    // this process (same bundle ID as the one being launched) dies while
    // Launch Services is still mid-handshake on the pending launch, LS
    // coalesces/aborts it and the new instance never appears. Controller
    // verified zero whereamip processes running after a real restart.
    //
    // Fix: spawn a detached waiter that *polls for our PID to actually
    // disappear* (`kill -0` merely tests whether a process exists — no
    // signal sent, not a kill) before running `open`, then terminate
    // ourselves immediately with no arbitrary delay at all. The waiter can
    // only reach `open` after we are provably gone, closing the exact race
    // window LS was hitting. Process children are never tied to the
    // spawning app's lifecycle in a way `NSApp.terminate()` could kill —
    // POSIX reparents orphaned children to survive their parent's exit —
    // so the waiter genuinely outlives us; verified this empirically too
    // (see the manual relaunch smoke test in the commit for this fix).
    func relaunch(from path: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Path travels via environment rather than shell string
        // interpolation, sidestepping shell quoting/escaping entirely —
        // today's paths never contain quotes, but this doesn't rely on that
        // staying true forever.
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$RELAUNCH_PATH\""
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", script]
        waiter.environment = ["RELAUNCH_PATH": path]
        do {
            try waiter.run()
        } catch {
            // A swallowed spawn failure was part of why the field bug was
            // silent: if the waiter never launches, terminating anyway would
            // leave the user with no app running at all and no clue why.
            // Log it and bail out instead — doing nothing is strictly better
            // than vanishing with nothing to show for it.
            Log.monitor.error("relaunch: failed to spawn waiter for \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        NSApp.terminate(nil)   // waiter fires only once our PID is truly gone — no race
    }

    func eventsHappened(_ events: [Event]) {
        guard settings.notificationsEnabled else { return }
        for event in events {
            guard let (title, body) = NotificationText.text(for: event) else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // Rebuild the menu fresh on every OPEN (spec §4) — but only once per open.
    //
    // menuNeedsUpdate also fires on every keydown while the menu is tracking, ⌥ presses and
    // releases included, and rebuilding there tore the item views out of the open menu on
    // each one (visible jump, lost hover highlight — field-reported on v0.5). The alternate
    // pair never needed it: AppKit swaps those natively. MenuTrackingSession (in the UI
    // target, where it is unit-tested) holds the once-per-session rule and the reasoning,
    // including why a mid-open state refresh deliberately does not appear until the next open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menuSession.updateIfNeeded(menu) { self.buildMenu() }
    }

    // Ends the tracking session, so the next open builds from fresh state. Also the reason
    // nothing needs to clear this flag on state changes: the menu is only ever stale while
    // it is open, and closing it is what makes it current again.
    func menuDidClose(_ menu: NSMenu) {
        menuSession.trackingEnded()
    }

    private func buildMenu() -> NSMenu {
        MenuBuilder.build(
            state: lastState, style: settings.menuBarStyle,
            notificationsEnabled: settings.notificationsEnabled,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            availableUpdate: availableUpdate, updatesEnabled: settings.updatesEnabled,
            dnsProbeEnabled: settings.dnsProbeEnabled,
            restartUpdate: restartUpdate, applicationsLinked: ApplicationsLink.isLinked(),
            lastChecked: lastChecked,
            actions: MenuActions(
                copyIP: { [weak self] in
                    guard let ip = self?.lastState.exit?.ip else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                },
                // Every other copy row hands its finished payload here — the text
                // itself is derived in MenuBuilder from the same state this menu
                // was built with (see MenuActions.copyText), so this end stays one
                // pasteboard write and nothing else. Local clipboard only: no copy
                // action in this app sends anything anywhere.
                copyText: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                },
                refresh: { [weak self] in
                    guard let self else { return }
                    self.setManualRefreshIndicator(true)
                    Task {
                        await self.runMonitorRefresh(full: true)
                        // Unconditional re-render: Monitor.apply() only calls
                        // onChange when the new state actually differs from
                        // the old one (`guard next != old else { return }`)
                        // — a refresh that confirms "nothing changed" would
                        // never fire onChange/stateChanged() on its own, and
                        // the dim indicator set above would stick forever.
                        // Always pull currentState() and re-render explicitly
                        // instead of relying on onChange for this one path,
                        // then clear the dim now that fresh state is showing.
                        self.stateChanged(await self.monitor.currentState())
                        self.setManualRefreshIndicator(false)
                    }
                    self.checkForUpdates()
                },
                setStyle: { [weak self] style in
                    self?.settings.menuBarStyle = style
                    if let s = self?.lastState { self?.stateChanged(s) }
                },
                toggleNotifications: { [weak self] in
                    guard let self else { return }
                    if !settings.notificationsEnabled {
                        NotificationPermissionFlow.requestEnable { [weak self] granted, needsSystemSettings in
                            guard let self else { return }
                            if needsSystemSettings {
                                // The menu has no inline-label surface (unlike the
                                // welcome window's hint button) — go straight to
                                // System Settings instead of showing a hint.
                                NotificationPermissionFlow.openSystemSettings()
                            } else {
                                self.settings.notificationsEnabled = granted
                            }
                        }
                    } else {
                        settings.notificationsEnabled = false
                    }
                },
                toggleLaunchAtLogin: {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    } else {
                        try? SMAppService.mainApp.register()
                    }
                },
                toggleApplicationsLink: {
                    // Best-effort, same convention as toggleLaunchAtLogin above:
                    // the menu has no inline surface for an error message, so a
                    // failure (e.g. a real, non-symlink /Applications/WhereAmIP.app
                    // someone created) just leaves the checkbox reflecting
                    // whatever the actual on-disk state still is.
                    try? ApplicationsLink.setLinked(!ApplicationsLink.isLinked(), bundlePath: Bundle.main.bundlePath)
                },
                showWelcomeWindow: { [weak self] in
                    // Manual re-show, bypasses shouldShowWelcome entirely —
                    // always shows regardless of welcomedMilestone. Clicking
                    // Done afterwards just re-stores the same milestone
                    // value, which is harmless.
                    guard let self else { return }
                    self.welcomeWindowController = self.present(self.welcomeWindowController) {
                        WelcomeWindowController(settings: self.settings)
                    }
                },
                showHelpWindow: { [weak self] in
                    // Held in its own property, independent of the welcome
                    // window's: the two coexist, and opening one must never
                    // close, move, or reset the other.
                    guard let self else { return }
                    self.helpWindowController = self.present(self.helpWindowController) {
                        HelpWindowController()
                    }
                },
                quit: { NSApp.terminate(nil) },
                copyUpdateCommand: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew upgrade whereamip", forType: .string)
                },
                toggleUpdateChecks: { [weak self] in
                    guard let self else { return }
                    settings.updatesEnabled.toggle()
                    if settings.updatesEnabled {
                        self.checkForUpdates()
                    } else {
                        self.availableUpdate = nil
                    }
                },
                toggleDNSProbe: { [weak self] in
                    guard let self else { return }
                    self.settings.dnsProbeEnabled.toggle()
                    Task { await self.monitor.fullRefresh() }
                },
                restartAction: { [weak self] in
                    guard let self, let appPath = InstalledVersion.onDisk(bundlePath: Bundle.main.bundlePath)?.appPath
                    else { return }
                    self.relaunch(from: appPath)
                },
                restartApp: { [weak self] in
                    guard let self else { return }
                    self.relaunch(from: Bundle.main.bundlePath)
                }))
    }
}

struct AppRoute: RouteSnapshotting {
    func snapshot() -> RouteInfo {
        let bundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return RouteInspector.snapshot(runningBundleIDs: bundleIDs)
    }
}
