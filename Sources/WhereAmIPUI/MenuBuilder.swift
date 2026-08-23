import AppKit
import WhereAmIPCore

public struct MenuActions {
    public var copyIP: () -> Void
    /// Every copy row added after the original exit-IP one hands its finished
    /// payload to this single closure instead of getting a closure of its own:
    /// the payload is derived purely from the state the builder already has
    /// (`DiagnosticsReport.text`, the two exit addresses, the resolver lists), so
    /// computing it HERE keeps it unit-testable without an AppDelegate, and leaves
    /// the app with one trivial "put this string on the pasteboard" implementation
    /// rather than four near-identical ones. `copyIP` stays as it was.
    public var copyText: (String) -> Void
    public var refresh: () -> Void
    public var setStyle: (MenuBarStyle) -> Void
    public var toggleNotifications: () -> Void
    public var toggleLaunchAtLogin: () -> Void
    public var toggleApplicationsLink: () -> Void
    public var showWelcomeWindow: () -> Void
    public var showHelpWindow: () -> Void
    public var quit: () -> Void
    public var copyUpdateCommand: () -> Void
    public var toggleUpdateChecks: () -> Void
    public var toggleDNSProbe: () -> Void
    public var restartAction: () -> Void
    public var restartApp: () -> Void
    public init(copyIP: @escaping () -> Void = {},
                copyText: @escaping (String) -> Void = { _ in },
                refresh: @escaping () -> Void = {},
                setStyle: @escaping (MenuBarStyle) -> Void = { _ in },
                toggleNotifications: @escaping () -> Void = {},
                toggleLaunchAtLogin: @escaping () -> Void = {},
                toggleApplicationsLink: @escaping () -> Void = {},
                showWelcomeWindow: @escaping () -> Void = {},
                showHelpWindow: @escaping () -> Void = {},
                quit: @escaping () -> Void = {},
                copyUpdateCommand: @escaping () -> Void = {},
                toggleUpdateChecks: @escaping () -> Void = {},
                toggleDNSProbe: @escaping () -> Void = {},
                restartAction: @escaping () -> Void = {},
                restartApp: @escaping () -> Void = {}) {
        self.copyIP = copyIP; self.copyText = copyText
        self.refresh = refresh; self.setStyle = setStyle
        self.toggleNotifications = toggleNotifications
        self.toggleLaunchAtLogin = toggleLaunchAtLogin; self.quit = quit
        self.toggleApplicationsLink = toggleApplicationsLink
        self.showWelcomeWindow = showWelcomeWindow
        self.showHelpWindow = showHelpWindow
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
            menu.addItem(action(L10n.string(.menuUpdateRestart, restartUpdate)) {
                actions.restartAction()
            })
            menu.addItem(.separator())
        } else if let availableUpdate {
            // Quiet update hint — never a popup or badge, just the first row when
            // a newer release exists. Clicking copies the brew command; the app
            // itself never downloads or modifies anything.
            menu.addItem(action(L10n.string(.menuUpdateAvailable, availableUpdate)) {
                actions.copyUpdateCommand()
            })
            menu.addItem(.separator())
        }

        // Header + warnings
        if state.connectivity == .offline {
            menu.addItem(info(L10n.string(.menuOffline)))
            // Same predicate the pasted diagnostics report uses (ExitState, warning
            // visibility) — identical behavior to the inline check this replaces,
            // but the two frontends can no longer drift on what counts as a warning.
            if state.showsHijackWarning {
                menu.addItem(info(L10n.string(.menuOfflineHijack)))
            }
            if let exit = state.exit {
                let flag = exit.countryCode.flatMap { Flags.emoji(countryCode: $0) } ?? ""
                menu.addItem(info(L10n.string(.menuOfflineLastSeen,
                                              timeFormatter.string(from: exit.fetchedAt), flag, exit.org ?? "")))
            }
        } else {
            // App icon, not the exit-country flag: the flag is already the
            // menu *bar* glyph directly above this dropdown, so repeating it
            // here was redundant. The icon instead identifies which app this
            // dropdown belongs to.
            let header = info(L10n.string(.menuHeader, whereamipVersion))
            header.image = appIconImage()
            menu.addItem(header)
            menu.addItem(.separator())
            // Warning row goes first in the info area — before the IP row — so it's
            // impossible to miss when a leak is confirmed.
            // Both gates come from the shared warning-visibility predicates in Core
            // (see ExitState): this branch is already the online one, so behavior is
            // unchanged — what's gained is that the diagnostics report reads the same
            // rules instead of a second copy of them.
            if state.showsIPv6LeakWarning {
                let org = state.exit6?.org ?? L10n.string(.menuOrgUnknown)
                let cc = state.exit6?.countryCode ?? "?"
                menu.addItem(info(L10n.string(.menuLeakIPv6, org, cc)))
            }
            switch state.visibleDNSLeak {
            case .confirmed:
                if let org = state.dns.egressOrg, !org.isEmpty {
                    menu.addItem(info(L10n.string(.menuLeakDNSWithOperator, org, state.dns.egressIP ?? "?")))
                } else {
                    menu.addItem(info(L10n.string(.menuLeakDNS, state.dns.egressIP ?? "?")))
                }
            case .suspected:
                menu.addItem(info(L10n.string(.menuLeakDNSSuspected)))
            case .none, .some:
                break
            }
            if let exit = state.exit {
                let ipItem = action(exit.ip, key: "c") { actions.copyIP() }
                ipItem.keyEquivalentModifierMask = [.command]
                menu.addItem(ipItem)
                // ⌥⌘C: the wider copy, revealed by holding Option. AppKit only
                // treats an item as an alternate of the one it DIRECTLY follows,
                // and only when both share a key equivalent — hence the exact
                // placement here rather than anywhere else in the info block.
                // Absent entirely without an IPv6 exit: a row promising two
                // addresses that copies one would be a lie, not a shortcut.
                if let exit6 = state.exit6 {
                    let bothItem = action(L10n.string(.menuCopyExitBoth), key: "c") {
                        // Addresses only, one per line. The rows above carry the
                        // city/operator labelling; a clipboard payload someone
                        // pastes into a terminal or a ticket must not.
                        actions.copyText([exit.ip, exit6.ip].joined(separator: "\n"))
                    }
                    bothItem.keyEquivalentModifierMask = [.command, .option]
                    bothItem.isAlternate = true
                    menu.addItem(bothItem)
                }
                let place = [exit.city, countryName(exit.countryCode)].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { menu.addItem(info(place)) }
                if let org = exit.org { menu.addItem(info(org)) }
                if let exit6 = state.exit6 {
                    menu.addItem(info(exit.splitLine(label: "IPv4")))
                    menu.addItem(info(exit6.splitLine(label: "IPv6")))
                }
            }
            menu.addItem(info(L10n.string(.menuSince, timeFormatter.string(from: state.since))))
            // Proof of freshness even when nothing changed: "Since" only moves
            // when the exit/connectivity/route actually differs (see Monitor
            // .apply), so a manual Refresh that confirms "still the same"
            // would otherwise look identical to no refresh ever happening.
            // Same formatter as Since — one source of truth, not a second
            // date-format decision to keep in sync.
            if let lastChecked {
                menu.addItem(info(L10n.string(.menuChecked, timeFormatter.string(from: lastChecked))))
            }
        }

        // VPN / relay block — only applicable lines
        var block: [NSMenuItem] = []
        if state.route.isVPN, let iface = state.route.defaultInterface {
            block.append(info(L10n.string(.menuRouteVPN,
                              state.route.vpnName ?? L10n.string(.menuRouteVPNUnknown), iface)))
        } else if let iface = state.route.defaultInterface, let kind = state.route.linkKind {
            block.append(info(L10n.string(.menuRouteLink, kind, iface)))
        }
        if case .active(_, let country) = state.privateRelay {
            let via = country.flatMap { Flags.emoji(countryCode: $0) }.map { L10n.string(.menuPrivateRelayVia, $0) } ?? ""
            block.append(info(L10n.string(.menuPrivateRelay, via)))
        }
        if let first = state.dns.resolvers.first {
            var line = L10n.string(.dnsRow, first.address)
            if let iface = first.interface { line += L10n.string(.dnsRowInterface, iface) }
            switch state.dns.encryption {
            case .doh: line += L10n.string(.dnsRowDoH)
            case .dot: line += L10n.string(.dnsRowDoT)
            case .plaintext: line += L10n.string(.dnsRowPlaintext)
            case .unknown: break
            }
            let uniqueCount = state.dns.uniqueAddressCount
            if uniqueCount > 1 { line += L10n.string(.dnsRowMore, uniqueCount - 1) }
            // Same summary the flat row always showed, now the title of a submenu holding the
            // full picture: every configured resolver, and every egress the probe round found.
            // NOT an `info` row — a disabled item can't be opened, so this one stays enabled
            // (like Settings) while everything inside it is info.
            let dnsItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            dnsItem.submenu = dnsSubmenu(state: state, dnsProbeEnabled: dnsProbeEnabled, actions: actions)
            block.append(dnsItem)
        }
        if !block.isEmpty {
            menu.addItem(.separator())
            block.forEach { menu.addItem($0) }
        }

        // Controls
        menu.addItem(.separator())
        // ⇧⌘C — the whole dropdown as pasteable text, for a bug report. Rendered
        // from exactly the state (and the same "Checked" stamp and DNS-probe
        // setting) this menu was built with, by the shared Core formatter the CLI's
        // `whereamip diagnostics` uses; nothing extra is measured, and nothing is
        // sent anywhere but the local pasteboard.
        let diagnostics = action(L10n.string(.menuCopyDiagnostics), key: "c") {
            actions.copyText(DiagnosticsReport.text(for: state, checked: lastChecked,
                                                    dnsProbeEnabled: dnsProbeEnabled))
        }
        diagnostics.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(diagnostics)

        let refresh = action(L10n.string(.menuRefresh), key: "r") { actions.refresh() }
        refresh.keyEquivalentModifierMask = [.command]
        menu.addItem(refresh)

        // ⌘? — Apple's own Help item is bound exactly like this. NO .shift, even
        // though "?" is typed with Shift on both US (Shift-/) and German (Shift-ß)
        // layouts: the HIG says not to add Shift to a shortcut using the upper
        // character of a two-character key, and a key equivalent matches on the
        // CHARACTER PRODUCED, Shift excepted. Adding .shift here would display as
        // ⇧⌘? and deviate from the platform — don't "fix" it back.
        let help = action(L10n.string(.menuHelp), key: "?") { actions.showHelpWindow() }
        help.keyEquivalentModifierMask = [.command]
        menu.addItem(help)

        let settings = NSMenuItem(title: L10n.string(.menuSettings), action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        // There is no persistent "debug mode" to show here — diagnostics exist only while
        // `whereamip debug` streams (nothing on disk, by design). The checkmark rows below
        // are the app's complete visible state. No version row here: the main dropdown
        // header already shows "WhereAmIP v<version>" — a submenu doesn't re-brand itself.
        let styleItem = NSMenuItem(title: L10n.string(.settingsStyle), action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        styleMenu.autoenablesItems = false
        for (key, value) in [(L10nKey.settingsStyleEmoji, MenuBarStyle.emoji),
                             (.settingsStyleCode, .code), (.settingsStyleImage, .image)] {
            let i = action(L10n.string(key)) { actions.setStyle(value) }
            i.state = (style == value) ? .on : .off
            styleMenu.addItem(i)
        }
        styleItem.submenu = styleMenu
        settingsMenu.addItem(styleItem)
        settingsMenu.addItem(.separator())
        let notify = action(L10n.string(.settingsNotifications)) { actions.toggleNotifications() }
        notify.state = notificationsEnabled ? .on : .off
        settingsMenu.addItem(notify)
        let login = action(L10n.string(.settingsLaunchAtLogin)) { actions.toggleLaunchAtLogin() }
        login.state = launchAtLogin ? .on : .off
        settingsMenu.addItem(login)
        let appsLink = action(L10n.string(.settingsApplicationsLink)) { actions.toggleApplicationsLink() }
        appsLink.state = applicationsLinked ? .on : .off
        settingsMenu.addItem(appsLink)
        let checkUpdates = action(L10n.string(.settingsUpdates)) { actions.toggleUpdateChecks() }
        checkUpdates.state = updatesEnabled ? .on : .off
        settingsMenu.addItem(checkUpdates)
        let dnsProbe = action(L10n.string(.settingsDNSProbe)) { actions.toggleDNSProbe() }
        dnsProbe.state = dnsProbeEnabled ? .on : .off
        settingsMenu.addItem(dnsProbe)
        settingsMenu.addItem(.separator())
        // Plain action (no checkmark, unlike the toggles above) — re-opens
        // the first-run window on demand, independent of whether it's
        // already been acknowledged.
        settingsMenu.addItem(action(L10n.string(.settingsWelcome)) { actions.showWelcomeWindow() })
        settings.submenu = settingsMenu
        menu.addItem(settings)

        menu.addItem(action(L10n.string(.menuRestart)) { actions.restartApp() })

        let quit = action(L10n.string(.menuQuit), key: "q") { actions.quit() }
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return menu
    }

    /// The DNS row's detail submenu: what macOS is configured to ask (local fact, always known)
    /// above what actually answered at the far end (measured, and only when the user allows the
    /// probe). Two labelled sections rather than one flat list — the two halves are different
    /// kinds of fact, and confusing "my router" with "the resolver that saw my query" is exactly
    /// what makes split-DNS setups unreadable.
    static func dnsSubmenu(state: ExitState, dnsProbeEnabled: Bool,
                           actions: MenuActions = MenuActions()) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(info(L10n.string(.dnsSectionConfigured)))
        // One row per unique ADDRESS: DNSConfigReader deliberately emits the same address once
        // globally and once per service, which is right for leak attribution and pure noise in
        // a list. The interfaces it was scoped to are collected onto that single row instead.
        var seen = Set<String>()
        for resolver in state.dns.resolvers where seen.insert(resolver.address).inserted {
            let interfaces = state.dns.resolvers
                .filter { $0.address == resolver.address }
                .compactMap(\.interface)
            var row = resolver.address
            if !interfaces.isEmpty {
                row = L10n.string(.dnsResolverInterfaces, row, interfaces.joined(separator: ", "))
            }
            menu.addItem(info(row))
        }

        var egressRows: [String] = []
        if !dnsProbeEnabled {
            // The opt-out is a fact worth stating here, where its absence would otherwise read
            // as "nothing answered". Never shows a stale measurement next to it.
            egressRows = [L10n.string(.dnsDisabled)]
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
            egressRows.append(L10n.string(.dnsForwarder, provider))
        }
        if !egressRows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(info(L10n.string(.dnsSectionEgress)))
            egressRows.forEach { menu.addItem(info($0)) }
        }

        // Bulk copy, one row per section above it, closing the submenu. Each label
        // names WHICH set it copies in that section's own vocabulary — "Configured
        // resolvers" → configured, "Queries answered by" → answering — because a
        // bare "Copy addresses" here would be ambiguous between the two lists it
        // sits under. No key equivalents: the rows are visible where they matter,
        // and a submenu is the wrong place to spend another ⌘-something.
        //
        // Row text and clipboard text are different products: the rows above read
        // "192.168.178.1 — en0" and "185.44.108.99 — WoodyNet, Inc. (Berlin, DE) ·
        // UDP"; the payload is the bare addresses, one per line, ready to paste
        // into a resolver field or a ticket.
        var copyRows: [NSMenuItem] = []
        let configured = orderedUniqueAddresses(state.dns.resolvers)
        if !configured.isEmpty {
            copyRows.append(action(L10n.string(.dnsCopyConfigured)) {
                actions.copyText(configured.joined(separator: "\n"))
            })
        }
        // Mirrors exactly what the egress section above actually shows: nothing to
        // copy when the probe is off (there is no measurement at all) or when
        // neither the enumeration nor the beacon fallback produced an address.
        var answering: [String] = []
        if dnsProbeEnabled {
            answering = state.dns.egressResolvers.map(\.ip)
            if answering.isEmpty, let egressIP = state.dns.egressIP { answering = [egressIP] }
        }
        if !answering.isEmpty {
            copyRows.append(action(L10n.string(.dnsCopyAnswering)) {
                actions.copyText(answering.joined(separator: "\n"))
            })
        }
        if !copyRows.isEmpty {
            menu.addItem(.separator())
            copyRows.forEach { menu.addItem($0) }
        }
        return menu
    }

    /// Configured resolver addresses, each once, in the order they were read — the
    /// same dedup rule the rows above apply (`DNSConfigReader` deliberately emits an
    /// address once globally and once per service).
    static func orderedUniqueAddresses(_ resolvers: [DNSResolver]) -> [String] {
        var seen = Set<String>()
        return resolvers.map(\.address).filter { seen.insert($0).inserted }
    }

    static func countryName(_ iso: String?) -> String? {
        guard let iso else { return nil }
        return Locale(identifier: "en_US").localizedString(forRegionCode: iso) ?? iso
    }
}
