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

    // Sized down from the full-resolution app icon for a menu row (NSMenuItem
    // images render best around 16-18pt) — replaces the header row's flag
    // emoji, which was redundant there: it's already visible in the menu bar
    // directly above. Deliberately `NSApplication.shared` rather than the
    // bare `NSApp` global: `NSApp` is an implicitly-unwrapped optional that
    // only gets populated as a side effect of `NSApplicationMain`/an app
    // actually launching — under `swift test` (no real app launch) it's
    // nil, and force-unwrapping it crashed the whole test bundle. `.shared`
    // is the safe, always-lazily-initialized accessor. It returns the
    // bundle's actual icon in a real .app; in the test environment (no real
    // bundle) AppKit hands back its generic icon instead, which is fine —
    // tests only assert an image is present, not its pixels. Copied before
    // resizing so this never mutates the shared instance (which other
    // code/AppKit itself may also read).
    static func appIconImage(size: CGFloat = 18) -> NSImage? {
        guard let icon = NSApplication.shared.applicationIconImage?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    public static func build(state: ExitState, style: MenuBarStyle,
                             notificationsEnabled: Bool, launchAtLogin: Bool,
                             availableUpdate: String? = nil, updatesEnabled: Bool = true,
                             dnsProbeEnabled: Bool = true,
                             restartUpdate: String? = nil, applicationsLinked: Bool = false,
                             lastChecked: Date? = nil,
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
            // App icon, not the exit-country flag: the flag is already the
            // menu *bar* glyph directly above this dropdown, so repeating it
            // here was redundant. The icon instead identifies which app this
            // dropdown belongs to.
            let header = info("WhereAmIP v\(whereamipVersion)")
            header.image = appIconImage()
            menu.addItem(header)
            menu.addItem(.separator())
            // Warning row goes first in the info area — before the IP row — so it's
            // impossible to miss when a leak is confirmed.
            if state.ipv6Leak {
                let org = state.exit6?.org ?? "your ISP"
                let cc = state.exit6?.countryCode ?? "?"
                menu.addItem(info("⚠️ IPv6 leak — v6 exits via \(org) (\(cc))"))
            }
            if state.dns.leak == .confirmed {
                if let org = state.dns.egressOrg, !org.isEmpty {
                    menu.addItem(info("⚠️ DNS leak — queries answered via \(org) (\(state.dns.egressIP ?? "?"))"))
                } else {
                    menu.addItem(info("⚠️ DNS leak — queries answered via \(state.dns.egressIP ?? "?")"))
                }
            } else if state.dns.leak == .suspected {
                menu.addItem(info("DNS leak suspected — resolver exits outside the tunnel"))
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
            // Proof of freshness even when nothing changed: "Since" only moves
            // when the exit/connectivity/route actually differs (see Monitor
            // .apply), so a manual Refresh that confirms "still the same"
            // would otherwise look identical to no refresh ever happening.
            // Same formatter as Since — one source of truth, not a second
            // date-format decision to keep in sync.
            if let lastChecked {
                menu.addItem(info("Checked: \(timeFormatter.string(from: lastChecked))"))
            }
        }

        // VPN / relay block — only applicable lines
        var block: [NSMenuItem] = []
        if state.route.isVPN, let iface = state.route.defaultInterface {
            block.append(info("VPN: \(state.route.vpnName ?? "unknown") (\(iface)) owns default route"))
        } else if let iface = state.route.defaultInterface, let kind = state.route.linkKind {
            block.append(info("Route: \(kind) (\(iface))"))
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
            let uniqueCount = state.dns.uniqueAddressCount
            if uniqueCount > 1 { line += "  (+\(uniqueCount - 1) more)" }
            // Same summary the flat row always showed, now the title of a submenu holding the
            // full picture: every configured resolver, and every egress the probe round found.
            // NOT an `info` row — a disabled item can't be opened, so this one stays enabled
            // (like Settings) while everything inside it is info.
            let dnsItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            dnsItem.submenu = dnsSubmenu(state: state, dnsProbeEnabled: dnsProbeEnabled)
            block.append(dnsItem)
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
        // `whereamip debug` streams (nothing on disk, by design). The checkmark rows below
        // are the app's complete visible state. No version row here: the main dropdown
        // header already shows "WhereAmIP v<version>" — a submenu doesn't re-brand itself.
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
        let dnsProbe = action("Check for DNS Leaks") { actions.toggleDNSProbe() }
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

    /// The DNS row's detail submenu: what macOS is configured to ask (local fact, always known)
    /// above what actually answered at the far end (measured, and only when the user allows the
    /// probe). Two labelled sections rather than one flat list — the two halves are different
    /// kinds of fact, and confusing "my router" with "the resolver that saw my query" is exactly
    /// what makes split-DNS setups unreadable.
    static func dnsSubmenu(state: ExitState, dnsProbeEnabled: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(info("Configured resolvers"))
        // One row per unique ADDRESS: DNSConfigReader deliberately emits the same address once
        // globally and once per service, which is right for leak attribution and pure noise in
        // a list. The interfaces it was scoped to are collected onto that single row instead.
        var seen = Set<String>()
        for resolver in state.dns.resolvers where seen.insert(resolver.address).inserted {
            let interfaces = state.dns.resolvers
                .filter { $0.address == resolver.address }
                .compactMap(\.interface)
            var row = resolver.address
            if !interfaces.isEmpty { row += " — \(interfaces.joined(separator: ", "))" }
            menu.addItem(info(row))
        }

        var egressRows: [String] = []
        if !dnsProbeEnabled {
            // The opt-out is a fact worth stating here, where its absence would otherwise read
            // as "nothing answered". Never shows a stale measurement next to it.
            egressRows = ["DNS check disabled"]
        } else if !state.dns.egressResolvers.isEmpty {
            egressRows = state.dns.egressResolvers.map(\.displayLine)
        } else if let egressIP = state.dns.egressIP {
            // Enumeration found nothing and the beacon fallback answered instead — one row,
            // formatted by the same rules so the two sources can't look like different features.
            egressRows = [EgressResolver(ip: egressIP, operatorName: state.dns.egressOrg).displayLine]
        }
        // Neutral attribution, never a claim about encryption and never a warning: whether the
        // router's own hop upstream is encrypted is configured there and unobservable from here.
        // Fed from egressResolvers, which is deliberately empty on a beacon-only fallback round
        // — so the row is absent on those refreshes rather than attributed from one lone
        // measurement. Accepted: the enumeration is the normal path, the fallback the exception.
        if let provider = DNSForwarderHint.provider(configured: state.dns.resolvers,
                                                    egress: state.dns.egressResolvers), dnsProbeEnabled {
            egressRows.append("Router forwards to \(provider) — encryption of that hop is set on the router")
        }
        if !egressRows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(info("Queries answered by"))
            egressRows.forEach { menu.addItem(info($0)) }
        }
        return menu
    }

    static func countryName(_ iso: String?) -> String? {
        guard let iso else { return nil }
        return Locale(identifier: "en_US").localizedString(forRegionCode: iso) ?? iso
    }
}
