import CGtk
import Foundation
import Glibc
import WhereAmIPCore
import WhereAmIPUI
import WhereAmIPLinuxUI

/// The Linux counterpart of the macOS `AppDelegate`: one Monitor, one panel indicator, the
/// same timers and refresh rules — every decision that can live in Core or in
/// `WhereAmIPLinuxUI` lives there, and what is left here is GTK plumbing.
///
/// Threading: everything in this class runs on the GTK main loop. Swift concurrency is used
/// for the Monitor's work, and every result comes back through `MainThread.async` — never
/// through `@MainActor`, which `gtk_main()` does not service (see MainThread).
final class IndicatorApp {
    let settings = Settings()
    let updateChecker = UpdateChecker()
    let executablePath = SelfExecutable.path()
    lazy var installChannel = InstallChannel.detect(path: executablePath)
    let icons = PanelIconRenderer(directory: PanelIconRenderer.defaultDirectory())
    let indicator: UnsafeMutablePointer<AppIndicator>
    var menu: MenuRenderer!
    var monitor: Monitor!
    var networkWatcher: NetworkWatcher?

    var lastState = ExitState()
    /// Proof of freshness for the "Checked" row; set after every refresh this app runs.
    var lastChecked: Date?
    var availableUpdate: String?
    var restartUpdate: String?
    var lastUpdateCheckAttempt: Date?
    var lastDiskCheckAt: Date?
    var manualRefreshInProgress = false
    var helpWindow: HelpWindow?
    var welcomeWindow: WelcomeWindow?

    init() {
        indicator = app_indicator_new(LinuxDesktopEntry.id, "", APP_INDICATOR_CATEGORY_APPLICATION_STATUS)
        app_indicator_set_title(indicator, "WhereAmIP")
        app_indicator_set_icon_theme_path(indicator, icons.directory)
        // One Settings instance for every string lookup, rather than a fresh UserDefaults per
        // lookup — on Linux each one is a cache to keep in step (see Settings.refreshFromDisk).
        L10n.languageSetting = { [settings] in settings.language }
        menu = MenuRenderer(indicator: indicator) { [weak self] action in self?.perform(action) }
    }

    func start() {
        render()
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)

        monitor = Monitor(
            geo: GeoProviderChain(), probe: ConnectivityProbe(),
            route: LinuxRoute(), httpIP: HTTPIPFetcher(), stackIP: StackPinnedIP(),
            dnsProbeEnabled: { [settings] in settings.dnsProbeEnabled },
            relayRanges: RelayRanges.bundled(),
            onChange: { [weak self] state in MainThread.async { self?.stateChanged(state) } },
            onEvents: { [weak self] events in MainThread.async { self?.eventsHappened(events) } })

        networkWatcher = NetworkWatcher { [weak self] in
            guard let self else { return }
            // Same exception as the macOS path monitor: pathChanged() debounces and refreshes
            // inside the Monitor, so this trigger does not move "Checked" by itself.
            Task { await self.monitor.pathChanged() }
        }
        networkWatcher?.start()
        ResumeWatch.start { [weak self] in self?.runMonitorRefresh(full: true) }

        runMonitorRefresh(full: true)
        checkForUpdates()
        MainThread.every(seconds: 30) { [weak self] in self?.runMonitorRefresh(full: false) }
        MainThread.every(seconds: 300) { [weak self] in self?.runMonitorRefresh(full: true) }
        // Launch + daily + manual Refresh, plus the six-hourly opportunistic check that
        // rides along with full refreshes — the same cadence as macOS (UpdateCheckSchedule).
        MainThread.every(seconds: 86_400) { [weak self] in self?.checkForUpdates() }

        if LinuxContent.shouldShowWelcome(storedMilestone: settings.welcomedMilestone) {
            showWelcome()
        }
        // A panel host can register a little after us at login; look twice before telling
        // anyone the icon is invisible.
        MainThread.after(milliseconds: 8_000) { [weak self] in
            guard let self, !PanelSupport.canShowIndicator() else { return }
            MainThread.after(milliseconds: 22_000) { [weak self] in self?.warnIfIndicatorInvisible() }
        }
    }

    // MARK: - refresh

    func runMonitorRefresh(full: Bool, then: (() -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            if full { await self.monitor.fullRefresh() } else { await self.monitor.probeTick() }
            // Pulled explicitly, not left to onChange: a refresh that confirms "nothing
            // changed" fires no onChange, and the Checked row must still move.
            let state = await self.monitor.currentState()
            MainThread.async {
                self.lastState = state
                self.lastChecked = Date()
                if full, UpdateCheckSchedule.shouldAttempt(lastAttempt: self.lastUpdateCheckAttempt,
                                                           enabled: self.settings.updatesEnabled) {
                    self.checkForUpdates()
                }
                then?()
                self.render()
            }
        }
    }

    func stateChanged(_ state: ExitState) {
        lastState = state
        render()
        // Throttled, as on macOS: a background reinstall should surface soon, without a
        // process launch on every state change.
        let now = Date()
        if lastDiskCheckAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            lastDiskCheckAt = now
            checkInstalledVersion()
        }
    }

    func eventsHappened(_ events: [Event]) {
        settings.refreshFromDisk()
        guard settings.notificationsEnabled else { return }
        for event in events {
            guard let (title, body) = NotificationText.text(for: event) else { continue }
            wai_notify("WhereAmIP", LinuxDesktopEntry.id, title, body, LinuxDesktopEntry.id)
        }
    }

    /// The panel icon and the menu, both from current state. Cheap enough to run on every
    /// change: icons are drawn once per distinct look, and an unchanged menu structure is
    /// updated in place.
    func render() {
        settings.refreshFromDisk()
        let icon = PanelIcon.forState(lastState, style: settings.menuBarStyle, dimmed: manualRefreshInProgress)
        if let name = icons.iconName(for: icon) {
            app_indicator_set_icon_full(indicator, name, icon.accessibleDescription)
        }
        menu.render(MenuModelBuilder.build(.init(
            state: lastState, style: settings.menuBarStyle,
            notificationsEnabled: settings.notificationsEnabled,
            launchAtLogin: LinuxDesktopEntry.isInstalled(at: LinuxDesktopEntry.path(.autostart)),
            launcherEntry: LinuxDesktopEntry.isInstalled(at: LinuxDesktopEntry.path(.launcher)),
            availableUpdate: availableUpdate, updatesEnabled: settings.updatesEnabled,
            dnsProbeEnabled: settings.dnsProbeEnabled, language: settings.language,
            restartUpdate: restartUpdate, lastChecked: lastChecked, installChannel: installChannel)))
    }

    // MARK: - actions

    func perform(_ action: MenuAction) {
        switch action {
        case .copyText(let text):
            // Local clipboard only — no copy action sends anything anywhere.
            wai_clipboard_set_text(text)
        case .openURL(let url):
            gtk_show_uri_on_window(nil, url, 0, nil)
        case .refresh:
            manualRefreshInProgress = true
            render()
            runMonitorRefresh(full: true) { [weak self] in self?.manualRefreshInProgress = false }
            checkForUpdates()
        case .setStyle(let style):
            settings.menuBarStyle = style
            render()
        case .setLanguage(let language):
            // Live, like macOS: every string is resolved at build time, and the menu is
            // rebuilt right here. Open windows keep theirs until reopened.
            settings.language = language
            render()
        case .toggleNotifications:
            settings.notificationsEnabled.toggle()
            render()
            welcomeWindow?.syncFromTruth()
        case .toggleLaunchAtLogin:
            toggleEntry(.autostart)
        case .toggleLauncherEntry:
            toggleEntry(.launcher)
        case .toggleUpdateChecks:
            settings.updatesEnabled.toggle()
            if settings.updatesEnabled { checkForUpdates() } else { availableUpdate = nil }
            render()
        case .toggleDNSProbe:
            settings.dnsProbeEnabled.toggle()
            render()
            runMonitorRefresh(full: true)
        case .showWelcome:
            showWelcome()
        case .showHelp:
            if let helpWindow, helpWindow.isOpen { helpWindow.present(); return }
            helpWindow = HelpWindow()
            helpWindow?.present()
        case .restartToUpdate:
            relaunch(executablePath)
        case .restart:
            relaunch(executablePath)
        case .quit:
            gtk_main_quit()
        }
    }

    func toggleEntry(_ kind: LinuxDesktopEntry.Kind) {
        let path = LinuxDesktopEntry.path(kind)
        setEntry(kind, installed: !LinuxDesktopEntry.isInstalled(at: path))
    }

    func setEntry(_ kind: LinuxDesktopEntry.Kind, installed: Bool) {
        do {
            try LinuxDesktopEntry.setInstalled(installed, kind: kind, executable: executablePath)
        } catch {
            // Best effort, like the macOS toggles: the checkmark keeps showing what is
            // actually on disk, and the reason goes to the log.
            Log.monitor.error("desktop entry: \(String(describing: error), privacy: .public)")
        }
        render()
        welcomeWindow?.syncFromTruth()
    }

    func showWelcome() {
        if let welcomeWindow, welcomeWindow.isOpen { welcomeWindow.present(); return }
        let entry = { (kind: LinuxDesktopEntry.Kind) in LinuxDesktopEntry.isInstalled(at: LinuxDesktopEntry.path(kind)) }
        welcomeWindow = WelcomeWindow(
            toggles: [
                .init(label: L10n.string(.settingsLaunchAtLogin), isOn: { entry(.autostart) },
                      set: { [weak self] on in self?.setEntry(.autostart, installed: on) }),
                .init(label: L10n.string(.settingsLauncherEntry), isOn: { entry(.launcher) },
                      set: { [weak self] on in self?.setEntry(.launcher, installed: on) }),
                .init(label: L10n.string(.settingsNotifications), isOn: { [settings] in settings.notificationsEnabled },
                      set: { [weak self] on in self?.settings.notificationsEnabled = on; self?.render() }),
            ],
            showsTrayHint: true,
            onDone: { [settings] in settings.welcomedMilestone = WelcomeContent.acknowledgedMilestone(for: .intro) })
        welcomeWindow?.present()
    }

    // MARK: - updates

    /// Passive, exactly as on macOS: learns whether a newer release exists and nothing else.
    func checkForUpdates() {
        checkInstalledVersion()
        guard settings.updatesEnabled else { return }
        lastUpdateCheckAttempt = Date()
        Task { [weak self] in
            guard let self else { return }
            let latest = await self.updateChecker.latestVersion()
            let newer = latest.map { SemVer.isNewer($0, than: whereamipVersion) } ?? false
            MainThread.async {
                self.availableUpdate = newer ? latest : nil
                self.render()
            }
        }
    }

    /// "The install replaced my files, but this process is the old binary": on Linux the
    /// kernel says so directly — `/proc/self/exe` gains a " (deleted)" suffix once the file
    /// we were started from has been replaced. The new copy's version then comes from the
    /// CLI installed beside it. Off the main loop, since it launches a process.
    func checkInstalledVersion() {
        guard SelfExecutable.wasReplaced else { restartUpdate = nil; return }
        let cli = (executablePath as NSString).deletingLastPathComponent + "/whereamip"
        DispatchQueue.global().async { [weak self] in
            let installed = SelfExecutable.version(ofCLI: cli)
            MainThread.async {
                guard let self else { return }
                self.restartUpdate = installed.flatMap { SemVer.isNewer($0, than: whereamipVersion) ? $0 : nil }
                self.render()
            }
        }
    }

    /// Restart: wait for this PID to be gone, then start the binary at `path` — the macOS
    /// relaunch's waiter, for the same reason (two copies must never overlap; the new one
    /// would find the instance lock still held and leave).
    func relaunch(_ path: String) {
        let pid = getpid()
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; exec \"$RELAUNCH_PATH\""]
        // The whole environment, not just the path: the new instance needs DISPLAY and the
        // session bus address to reach the panel at all.
        var environment = ProcessInfo.processInfo.environment
        environment["RELAUNCH_PATH"] = path
        waiter.environment = environment
        do {
            try waiter.run()
        } catch {
            Log.monitor.error("relaunch: failed to spawn waiter for \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        gtk_main_quit()
    }

    // MARK: - panel support

    func warnIfIndicatorInvisible() {
        guard !PanelSupport.canShowIndicator() else { return }
        let message = "WhereAmIP: no panel on this desktop shows app indicators, so the icon is invisible. "
            + "On elementary OS, install the AppIconTray indicator (see the README); `whereamip status` works meanwhile.\n"
        FileHandle.standardError.write(Data(message.utf8))
        wai_notify("WhereAmIP", LinuxDesktopEntry.id, L10n.string(.notificationNoTrayTitle),
                   L10n.string(.notificationNoTrayBody), LinuxDesktopEntry.id)
    }
}

struct LinuxRoute: RouteSnapshotting {
    func snapshot() -> RouteInfo { RouteInspector.snapshot(runningBundleIDs: []) }
}

enum PanelSupport {
    /// A StatusNotifierItem host is registered, or (on X11) a legacy system tray exists —
    /// the two places libayatana-appindicator can put the icon.
    static func canShowIndicator() -> Bool {
        wai_status_notifier_host_state() == 1 || wai_xembed_tray_present() != 0
    }
}

enum ResumeWatch {
    private static var handler: CallbackBox?

    static func start(_ onResume: @escaping () -> Void) {
        let box = CallbackBox(onResume)
        handler = box
        wai_watch_resume({ data in
            guard let data else { return }
            Unmanaged<CallbackBox>.fromOpaque(data).takeUnretainedValue().run()
        }, Unmanaged.passUnretained(box).toOpaque())
    }
}

enum SelfExecutable {
    private static let deletedSuffix = " (deleted)"

    private static var link: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")
    }

    /// The real path of the running binary, without the kernel's " (deleted)" marker.
    static func path() -> String {
        guard let link else { return CommandLine.arguments[0] }
        return link.hasSuffix(deletedSuffix) ? String(link.dropLast(deletedSuffix.count)) : link
    }

    static var wasReplaced: Bool { link?.hasSuffix(deletedSuffix) ?? false }

    /// `whereamip --version` of the CLI at `path`, or nil.
    static func version(ofCLI path: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return SemVer.parses(version) ? version : nil
    }
}
