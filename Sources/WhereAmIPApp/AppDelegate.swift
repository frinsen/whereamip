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
    var welcomeWindowController: WelcomeWindowController?

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
            Task { await self.monitor.pathChanged() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "whereamip.path"))

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        Task { await monitor.fullRefresh() }
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.monitor.probeTick() }
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.monitor.fullRefresh() }
        }
        // Cadence per spec: launch + once per 24h + on manual Refresh.
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    @objc func didWake() { Task { await monitor.fullRefresh() } }

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
                                                        ipv6Leak: state.ipv6Leak)
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
    // Services; terminating only after a short delay avoids racing that
    // handoff. The new instance recreates its own status item, so a brief
    // moment with no (or two) menu bar icons during the switch is expected
    // and acceptable.
    func relaunch(from path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", path]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
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

    // Rebuild the menu fresh on every open (spec §4)
    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = MenuBuilder.build(
            state: lastState, style: settings.menuBarStyle,
            notificationsEnabled: settings.notificationsEnabled,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            availableUpdate: availableUpdate, updatesEnabled: settings.updatesEnabled,
            restartUpdate: restartUpdate, applicationsLinked: ApplicationsLink.isLinked(),
            actions: MenuActions(
                copyIP: { [weak self] in
                    guard let ip = self?.lastState.exit?.ip else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                },
                refresh: { [weak self] in
                    guard let self else { return }
                    Task { await self.monitor.fullRefresh() }
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
                    self.welcomeWindowController = WelcomeWindowController(settings: self.settings)
                    self.welcomeWindowController?.show()
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
                restartAction: { [weak self] in
                    guard let self, let appPath = InstalledVersion.onDisk(bundlePath: Bundle.main.bundlePath)?.appPath
                    else { return }
                    self.relaunch(from: appPath)
                },
                restartApp: { [weak self] in
                    guard let self else { return }
                    self.relaunch(from: Bundle.main.bundlePath)
                }))
        menu.removeAllItems()
        fresh.items.forEach { item in
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}

struct AppRoute: RouteSnapshotting {
    func snapshot() -> RouteInfo {
        let bundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return RouteInspector.snapshot(runningBundleIDs: bundleIDs)
    }
}
