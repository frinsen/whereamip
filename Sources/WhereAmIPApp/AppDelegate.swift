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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = NSMenu()
        statusItem.menu!.delegate = self

        monitor = Monitor(
            geo: GeoProviderChain(), probe: ConnectivityProbe(),
            route: AppRoute(), httpIP: HTTPIPFetcher(),
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
        guard settings.updatesEnabled else { return }
        Task {
            let latest = await updateChecker.latestVersion()
            let newer = latest.map { SemVer.isNewer($0, than: whereamipVersion) } ?? false
            await MainActor.run { self.availableUpdate = newer ? latest : nil }
        }
    }

    func stateChanged(_ state: ExitState) {
        lastState = state
        let (title, image) = StatusItemRenderer.render(state.glyph(style: settings.menuBarStyle))
        statusItem.button?.title = title ?? ""
        statusItem.button?.image = image
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
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                            DispatchQueue.main.async { self.settings.notificationsEnabled = granted }
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
