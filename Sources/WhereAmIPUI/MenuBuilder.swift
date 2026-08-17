import AppKit
import WhereAmIPCore

public struct MenuActions {
    public var copyIP: () -> Void
    public var refresh: () -> Void
    public var setStyle: (MenuBarStyle) -> Void
    public var toggleNotifications: () -> Void
    public var toggleLaunchAtLogin: () -> Void
    public var toggleApplicationsLink: () -> Void
    public var showWelcomeWindow: () -> Void
    public var quit: () -> Void
    public var copyUpdateCommand: () -> Void
    public var toggleUpdateChecks: () -> Void
    public var toggleDNSProbe: () -> Void
    public var restartAction: () -> Void
    public var restartApp: () -> Void
    public init(copyIP: @escaping () -> Void = {}, refresh: @escaping () -> Void = {},
                setStyle: @escaping (MenuBarStyle) -> Void = { _ in },
                toggleNotifications: @escaping () -> Void = {},
                toggleLaunchAtLogin: @escaping () -> Void = {},
                toggleApplicationsLink: @escaping () -> Void = {},
                showWelcomeWindow: @escaping () -> Void = {},
                quit: @escaping () -> Void = {},
                copyUpdateCommand: @escaping () -> Void = {},
                toggleUpdateChecks: @escaping () -> Void = {},
                toggleDNSProbe: @escaping () -> Void = {},
                restartAction: @escaping () -> Void = {},
                restartApp: @escaping () -> Void = {}) {
        self.copyIP = copyIP; self.refresh = refresh; self.setStyle = setStyle
        self.toggleNotifications = toggleNotifications
        self.toggleLaunchAtLogin = toggleLaunchAtLogin; self.quit = quit
        self.toggleApplicationsLink = toggleApplicationsLink
        self.showWelcomeWindow = showWelcomeWindow
        self.copyUpdateCommand = copyUpdateCommand
        self.toggleUpdateChecks = toggleUpdateChecks
        self.toggleDNSProbe = toggleDNSProbe
        self.restartAction = restartAction
        self.restartApp = restartApp
    }
}

/// Target object holding closures so NSMenuItem actions can call them.
final class ActionTarget: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

public enum MenuBuilder {
    // Full date + time, including seconds (not time-only): an hours- or
    // days-old "Since"/"Last seen" otherwise looks identical to a minutes-old
    // one. Locale-aware via dateStyle/timeStyle (not a hardcoded format
    // string) so it renders correctly for the user's own locale, e.g.
    // "17.08.26, 10:45:32" in German locales vs "8/17/26, 10:45:32 AM" in US
    // English.
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
    }()

    static func info(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }
    static func action(_ title: String, key: String = "", _ run: @escaping () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(ActionTarget.fire), keyEquivalent: key)
        let t = ActionTarget(run)
        i.target = t
        i.representedObject = t   // retain the target
        return i
    }

    public static func build(state: ExitState, style: MenuBarStyle,
                             notificationsEnabled: Bool, launchAtLogin: Bool,
                             availableUpdate: String? = nil, updatesEnabled: Bool = true,
                             dnsProbeEnabled: Bool = true,
                             restartUpdate: String? = nil, applicationsLinked: Bool = false,
                             actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Restart-to-finish-update supersedes the plain "update available" row:
        // if the copy on disk is already newer than the running process (e.g.
        // `brew upgrade` ran but this process wasn't relaunched), advertising
        // "run brew upgrade" again would just tell the user to redo what
        // they've already done. Only one of these two rows is ever shown.
        if let restartUpdate {
            menu.addItem(action("↻ Restart to finish update (v\(restartUpdate))") {
                actions.restartAction()
            })
            menu.addItem(.separator())
        } else if let availableUpdate {
            // Quiet update hint — never a popup or badge, just the first row when
            // a newer release exists. Clicking copies the brew command; the app
            // itself never downloads or modifies anything.
            menu.addItem(action("⬆︎ Update v\(availableUpdate) available (brew upgrade whereamip)") {
                actions.copyUpdateCommand()
            })
            menu.addItem(.separator())
        }

        // Header + warnings
        if state.connectivity == .offline {
            menu.addItem(info("No internet connection"))
            if state.route.hijackRoutePresent {
                menu.addItem(info("⚠️ OpenVPN hijack routes present — tunnel likely dead"))
            }
            if let exit = state.exit {
                let flag = exit.countryCode.flatMap { Flags.emoji(countryCode: $0) } ?? ""
                menu.addItem(info("Last seen online: \(timeFormatter.string(from: exit.fetchedAt)) via \(flag) \(exit.org ?? "")"))
            }
        } else {
            let flag = state.exit?.countryCode.flatMap { Flags.emoji(countryCode: $0) } ?? "❓"
            menu.addItem(info("\(flag)  WhereAmIP v\(whereamipVersion)"))
            menu.addItem(.separator())
            // Warning row goes first in the info area — before the IP row — so it's
            // impossible to miss when a leak is confirmed.
            if state.ipv6Leak {
                let org = state.exit6?.org ?? "your ISP"
                let cc = state.exit6?.countryCode ?? "?"
                menu.addItem(info("⚠️ IPv6 leak — v6 exits via \(org) (\(cc))"))
            }
            if state.dns.leak == .confirmed {
                menu.addItem(info("⚠️ DNS leak — queries answered via \(state.dns.egressIP ?? "?")"))
            } else if state.dns.leak == .suspected {
                menu.addItem(info("DNS leak suspected — verifying…"))
            }
            if let exit = state.exit {
                let ipItem = action(exit.ip, key: "c") { actions.copyIP() }
                ipItem.keyEquivalentModifierMask = [.command]
                menu.addItem(ipItem)
                let place = [exit.city, countryName(exit.countryCode)].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { menu.addItem(info(place)) }
                if let org = exit.org { menu.addItem(info(org)) }
                if let exit6 = state.exit6 {
                    menu.addItem(info(exit.splitLine(label: "IPv4")))
                    menu.addItem(info(exit6.splitLine(label: "IPv6")))
                }
            }
            menu.addItem(info("Since \(timeFormatter.string(from: state.since))"))
        }

        // VPN / relay block — only applicable lines
        var block: [NSMenuItem] = []
        if state.route.isVPN, let iface = state.route.defaultInterface {
            block.append(info("VPN: \(state.route.vpnName ?? "unknown") (\(iface)) owns default route"))
        }
        if case .active(_, let country) = state.privateRelay {
            let via = country.flatMap { Flags.emoji(countryCode: $0) }.map { " via \($0)" } ?? ""
            block.append(info("Private Relay: ON — Safari exits\(via) elsewhere"))
        }
        if let first = state.dns.resolvers.first {
            var line = "DNS: \(first.address)"
            if let iface = first.interface { line += " via \(iface)" }
            switch state.dns.encryption {
            case .doh: line += " · DoH"
            case .dot: line += " · DoT"
            case .plaintext: line += " · plaintext"
            case .unknown: break
            }
            if state.dns.resolvers.count > 1 { line += "  (+\(state.dns.resolvers.count - 1) more)" }
            block.append(info(line))
        }
        if !block.isEmpty {
            menu.addItem(.separator())
            block.forEach { menu.addItem($0) }
        }

        // Controls
        menu.addItem(.separator())
        let refresh = action("Refresh", key: "r") { actions.refresh() }
        refresh.keyEquivalentModifierMask = [.command]
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        // There is no persistent "debug mode" to show here — diagnostics exist only while
        // `whereamip debug` streams (nothing on disk, by design). Version + the checkmark
        // rows below are the app's complete visible state.
        settingsMenu.addItem(info("WhereAmIP v\(whereamipVersion)"))
        settingsMenu.addItem(.separator())
        let styleItem = NSMenuItem(title: "Menu Bar Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        styleMenu.autoenablesItems = false
        for (title, value) in [("Emoji flag", MenuBarStyle.emoji), ("ISO country code", .code), ("Flag image", .image)] {
            let i = action(title) { actions.setStyle(value) }
            i.state = (style == value) ? .on : .off
            styleMenu.addItem(i)
        }
        styleItem.submenu = styleMenu
        settingsMenu.addItem(styleItem)
        settingsMenu.addItem(.separator())
        let notify = action("Show Notifications") { actions.toggleNotifications() }
        notify.state = notificationsEnabled ? .on : .off
        settingsMenu.addItem(notify)
        let login = action("Launch at Login") { actions.toggleLaunchAtLogin() }
        login.state = launchAtLogin ? .on : .off
        settingsMenu.addItem(login)
        let appsLink = action("Add to Applications folder") { actions.toggleApplicationsLink() }
        appsLink.state = applicationsLinked ? .on : .off
        settingsMenu.addItem(appsLink)
        let checkUpdates = action("Check for Updates") { actions.toggleUpdateChecks() }
        checkUpdates.state = updatesEnabled ? .on : .off
        settingsMenu.addItem(checkUpdates)
        let dnsProbe = action("Check DNS egress") { actions.toggleDNSProbe() }
        dnsProbe.state = dnsProbeEnabled ? .on : .off
        settingsMenu.addItem(dnsProbe)
        settingsMenu.addItem(.separator())
        // Plain action (no checkmark, unlike the toggles above) — re-opens
        // the first-run window on demand, independent of whether it's
        // already been acknowledged.
        settingsMenu.addItem(action("Show Welcome Window") { actions.showWelcomeWindow() })
        settings.submenu = settingsMenu
        menu.addItem(settings)

        menu.addItem(action("Restart WhereAmIP") { actions.restartApp() })

        let quit = action("Quit WhereAmIP", key: "q") { actions.quit() }
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return menu
    }

    static func countryName(_ iso: String?) -> String? {
        guard let iso else { return nil }
        return Locale(identifier: "en_US").localizedString(forRegionCode: iso) ?? iso
    }
}
