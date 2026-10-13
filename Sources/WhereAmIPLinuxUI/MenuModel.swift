import Foundation
import WhereAmIPCore
import WhereAmIPUI

/// What clicking a row does — data, not a closure, so the builder's decisions (which
/// payload a copy row carries, which command an update row offers) are assertable in tests
/// and the GTK layer stays one `switch` over this.
public enum MenuAction: Equatable, Sendable {
    case copyText(String)
    case openURL(String)
    case refresh
    case setStyle(MenuBarStyle)
    case setLanguage(String)
    case toggleNotifications
    case toggleLaunchAtLogin
    case toggleLauncherEntry
    case toggleUpdateChecks
    case toggleDNSProbe
    case showWelcome
    case showHelp
    case restartToUpdate
    case restart
    case quit
}

/// One row of the panel menu. `id` is stable across rebuilds of the same row, which is what
/// lets the GTK layer update an open menu in place (labels, checkmarks) instead of tearing
/// it down under the reader's pointer every time "Checked" ticks over.
public struct MenuItemModel: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A disabled, read-only row — the macOS `info` rows.
        case info
        case action(MenuAction)
        /// A checkmark setting; `radio` draws it as one of a set (style, language).
        case toggle(isOn: Bool, radio: Bool, action: MenuAction)
        case submenu([MenuItemModel])
        case separator
    }

    public var id: String
    public var title: String
    public var kind: Kind

    public init(id: String, title: String = "", kind: Kind) {
        self.id = id; self.title = title; self.kind = kind
    }

    /// The row's shape without its text or state: two menus with equal structure differ
    /// only in what can be updated in place.
    public var structure: String {
        switch kind {
        case .info: return "i:\(id)"
        case .action: return "a:\(id)"
        case .toggle(_, let radio, _): return "\(radio ? "r" : "t"):\(id)"
        case .submenu(let items): return "s:\(id)[\(items.map(\.structure).joined(separator: ","))]"
        case .separator: return "-:\(id)"
        }
    }
}

public extension Array where Element == MenuItemModel {
    var structure: String { map(\.structure).joined(separator: ",") }
}

/// The Linux panel menu, row for row the macOS dropdown that `MenuBuilder` builds — same
/// order, same strings (through `L10n`), same warning predicates, same copy payloads —
/// minus what a panel indicator cannot do:
///
///   - no key equivalents (an indicator menu is rendered by the panel, which does not
///     forward shortcuts), so the ⌥-revealed "copy both exits" alternate becomes an
///     ordinary row, shown only when there is an IPv6 exit to copy;
///   - no Private Relay row (Apple-only; Core never reports it active on Linux);
///   - "Add to Applications folder" is the applications-menu launcher entry, and the
///     milestone "What's New" entry is left out until there is a Linux release history
///     for it to describe.
///
/// When a row changes in MenuBuilder, change it here too; `MenuModelTests` pins the
/// shared parts against the same `L10n` keys and Core formatters MenuBuilderTests uses.
public enum MenuModelBuilder {
    /// Same pairing as `MenuBuilder.timeFormatter`: full date and time to the second, in
    /// the user's own locale.
    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium
        f.locale = AppLanguage.systemLocale
        return f
    }()

    public struct Input {
        public var state: ExitState
        public var style: MenuBarStyle
        public var notificationsEnabled: Bool
        public var launchAtLogin: Bool
        public var launcherEntry: Bool
        public var availableUpdate: String?
        public var updatesEnabled: Bool
        public var dnsProbeEnabled: Bool
        public var language: String
        public var restartUpdate: String?
        public var lastChecked: Date?
        public var installChannel: InstallChannel

        public init(state: ExitState, style: MenuBarStyle = .emoji,
                    notificationsEnabled: Bool = false, launchAtLogin: Bool = false,
                    launcherEntry: Bool = false, availableUpdate: String? = nil,
                    updatesEnabled: Bool = true, dnsProbeEnabled: Bool = true,
                    language: String = AppLanguage.system, restartUpdate: String? = nil,
                    lastChecked: Date? = nil, installChannel: InstallChannel = .direct) {
            self.state = state; self.style = style
            self.notificationsEnabled = notificationsEnabled; self.launchAtLogin = launchAtLogin
            self.launcherEntry = launcherEntry; self.availableUpdate = availableUpdate
            self.updatesEnabled = updatesEnabled; self.dnsProbeEnabled = dnsProbeEnabled
            self.language = language; self.restartUpdate = restartUpdate
            self.lastChecked = lastChecked; self.installChannel = installChannel
        }
    }

    private static func info(_ id: String, _ title: String) -> MenuItemModel {
        MenuItemModel(id: id, title: title, kind: .info)
    }
    private static func action(_ id: String, _ title: String, _ action: MenuAction) -> MenuItemModel {
        MenuItemModel(id: id, title: title, kind: .action(action))
    }
    private static func separator(_ id: String) -> MenuItemModel {
        MenuItemModel(id: id, kind: .separator)
    }

    public static func build(_ input: Input) -> [MenuItemModel] {
        let state = input.state
        var menu: [MenuItemModel] = []

        // Restart-to-finish-update supersedes "update available" — see MenuBuilder.
        if let restartUpdate = input.restartUpdate {
            menu.append(action("update", L10n.string(.menuUpdateRestart, restartUpdate), .restartToUpdate))
            menu.append(separator("sep.update"))
        } else if let availableUpdate = input.availableUpdate {
            if let command = UpdateChecker.upgradeCommand(for: input.installChannel) {
                menu.append(action("update", L10n.string(.menuUpdateAvailable, availableUpdate), .copyText(command)))
            } else {
                menu.append(action("update", L10n.string(.menuUpdateAvailableDownload, availableUpdate),
                                   .openURL(UpdateChecker.releasesURL)))
            }
            menu.append(separator("sep.update"))
        }

        if state.connectivity == .offline {
            menu.append(info("offline", L10n.string(.menuOffline)))
            if state.showsHijackWarning {
                menu.append(info("offline.hijack", L10n.string(.menuOfflineHijack)))
            }
            if let exit = state.exit {
                let flag = exit.countryCode.flatMap { Flags.emoji(countryCode: $0) } ?? ""
                menu.append(info("offline.lastSeen", L10n.string(.menuOfflineLastSeen,
                                                                  timeFormatter.string(from: exit.fetchedAt),
                                                                  flag, exit.org ?? "")))
            }
        } else {
            menu.append(info("header", L10n.string(.menuHeader, whereamipVersion)))
            menu.append(separator("sep.header"))
            if state.showsIPv6LeakWarning {
                menu.append(info("leak.ipv6", L10n.string(.menuLeakIPv6, state.exit6?.org ?? L10n.string(.menuOrgUnknown),
                                                            state.exit6?.countryCode ?? "?")))
            }
            switch state.visibleDNSLeak {
            case .confirmed:
                if let org = state.dns.egressOrg, !org.isEmpty {
                    menu.append(info("leak.dns", L10n.string(.menuLeakDNSWithOperator, org, state.dns.egressIP ?? "?")))
                } else {
                    menu.append(info("leak.dns", L10n.string(.menuLeakDNS, state.dns.egressIP ?? "?")))
                }
            case .suspected:
                menu.append(info("leak.dns", L10n.string(.menuLeakDNSSuspected)))
            default:
                break
            }
            if let exit = state.exit {
                menu.append(action("ip", exit.ip, .copyText(exit.ip)))
                if let exit6 = state.exit6 {
                    menu.append(action("ip.both", L10n.string(.menuCopyExitBoth),
                                       .copyText([exit.ip, exit6.ip].joined(separator: "\n"))))
                }
                let place = [exit.city, countryName(exit.countryCode)].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { menu.append(info("place", place)) }
                if let org = exit.org { menu.append(info("org", org)) }
                if let exit6 = state.exit6 {
                    menu.append(info("split4", exit.splitLine(label: "IPv4")))
                    menu.append(info("split6", exit6.splitLine(label: "IPv6")))
                }
            }
            menu.append(info("since", L10n.string(.menuSince, timeFormatter.string(from: state.since))))
            if let lastChecked = input.lastChecked {
                menu.append(info("checked", L10n.string(.menuChecked, timeFormatter.string(from: lastChecked))))
            }
        }

        var block: [MenuItemModel] = []
        if state.route.isVPN, let iface = state.route.defaultInterface {
            if let vpnName = state.route.vpnName {
                block.append(info("route", L10n.string(.menuRouteVPN, vpnName, iface)))
            } else {
                block.append(info("route", L10n.string(.menuRouteVPNUnnamed, iface)))
            }
        } else if let iface = state.route.defaultInterface, let kind = state.route.linkKind {
            block.append(info("route", L10n.string(.menuRouteLink, kind, iface)))
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
            block.append(MenuItemModel(id: "dns", title: line,
                                       kind: .submenu(dnsSubmenu(state: state, dnsProbeEnabled: input.dnsProbeEnabled))))
        }
        if !block.isEmpty {
            menu.append(separator("sep.block"))
            menu += block
        }

        menu.append(separator("sep.controls"))
        menu.append(action("diagnostics", L10n.string(.menuCopyDiagnostics),
                           .copyText(DiagnosticsReport.text(for: state, checked: input.lastChecked,
                                                            dnsProbeEnabled: input.dnsProbeEnabled))))
        menu.append(action("refresh", L10n.string(.menuRefresh), .refresh))
        menu.append(action("help", L10n.string(.menuHelp), .showHelp))
        menu.append(MenuItemModel(id: "settings", title: L10n.string(.menuSettings),
                                  kind: .submenu(settingsSubmenu(input))))
        menu.append(action("restart", L10n.string(.menuRestart), .restart))
        menu.append(action("quit", L10n.string(.menuQuit), .quit))
        return menu
    }

    static func settingsSubmenu(_ input: Input) -> [MenuItemModel] {
        func toggle(_ id: String, _ key: L10nKey, _ isOn: Bool, radio: Bool = false, _ action: MenuAction) -> MenuItemModel {
            MenuItemModel(id: id, title: L10n.string(key), kind: .toggle(isOn: isOn, radio: radio, action: action))
        }
        let styles: [MenuItemModel] = [(L10nKey.settingsStyleEmoji, MenuBarStyle.emoji),
                                       (.settingsStyleCode, .code), (.settingsStyleImage, .image)].map { key, value in
            toggle("style.\(value.rawValue)", key, input.style == value, radio: true, .setStyle(value))
        }
        let languages: [MenuItemModel] = [(L10nKey.settingsLanguageSystem, AppLanguage.system),
                                          (.settingsLanguageEnglish, "en"), (.settingsLanguageGerman, "de")].map { key, value in
            toggle("language.\(value)", key, input.language == value, radio: true, .setLanguage(value))
        }
        return [
            MenuItemModel(id: "style", title: L10n.string(.settingsStyle), kind: .submenu(styles)),
            MenuItemModel(id: "language", title: L10n.string(.settingsLanguage), kind: .submenu(languages)),
            separator("sep.settings.toggles"),
            toggle("notifications", .settingsNotifications, input.notificationsEnabled, .toggleNotifications),
            toggle("launchAtLogin", .settingsLaunchAtLogin, input.launchAtLogin, .toggleLaunchAtLogin),
            toggle("launcherEntry", .settingsLauncherEntry, input.launcherEntry, .toggleLauncherEntry),
            toggle("updates", .settingsUpdates, input.updatesEnabled, .toggleUpdateChecks),
            toggle("dnsProbe", .settingsDNSProbe, input.dnsProbeEnabled, .toggleDNSProbe),
            separator("sep.settings.windows"),
            action("welcome", L10n.string(.settingsWelcome), .showWelcome),
        ]
    }

    /// Same two sections and the same two bulk-copy rows as `MenuBuilder.dnsSubmenu`.
    static func dnsSubmenu(state: ExitState, dnsProbeEnabled: Bool) -> [MenuItemModel] {
        var menu: [MenuItemModel] = [info("dns.configured", L10n.string(.dnsSectionConfigured))]
        var seen = Set<String>()
        for resolver in state.dns.resolvers where seen.insert(resolver.address).inserted {
            let interfaces = state.dns.resolvers.filter { $0.address == resolver.address }.compactMap(\.interface)
            var row = resolver.address
            if !interfaces.isEmpty {
                row = L10n.string(.dnsResolverInterfaces, row, interfaces.joined(separator: ", "))
            }
            menu.append(info("dns.configured.\(resolver.address)", row))
        }

        var egressRows: [String] = []
        if !dnsProbeEnabled {
            egressRows = [L10n.string(.dnsDisabled)]
        } else if !state.dns.egressResolvers.isEmpty {
            egressRows = state.dns.egressResolvers.map(\.displayLine)
        } else if let egressIP = state.dns.egressIP {
            egressRows = [EgressResolver(ip: egressIP, operatorName: state.dns.egressOrg).displayLine]
        }
        if dnsProbeEnabled, let provider = DNSForwarderHint.provider(configured: state.dns.resolvers,
                                                                     egress: state.dns.egressResolvers) {
            egressRows.append(L10n.string(.dnsForwarder, provider))
        }
        if !egressRows.isEmpty {
            menu.append(separator("sep.dns.egress"))
            menu.append(info("dns.egress", L10n.string(.dnsSectionEgress)))
            for (index, row) in egressRows.enumerated() { menu.append(info("dns.egress.\(index)", row)) }
        }

        var copyRows: [MenuItemModel] = []
        let configured = orderedUniqueAddresses(state.dns.resolvers)
        if !configured.isEmpty {
            copyRows.append(action("dns.copy.configured", L10n.string(.dnsCopyConfigured),
                                   .copyText(configured.joined(separator: "\n"))))
        }
        var answering: [String] = []
        if dnsProbeEnabled {
            answering = state.dns.egressResolvers.map(\.ip)
            if answering.isEmpty, let egressIP = state.dns.egressIP { answering = [egressIP] }
        }
        if !answering.isEmpty {
            copyRows.append(action("dns.copy.answering", L10n.string(.dnsCopyAnswering),
                                   .copyText(answering.joined(separator: "\n"))))
        }
        if !copyRows.isEmpty {
            menu.append(separator("sep.dns.copy"))
            menu += copyRows
        }
        return menu
    }

    static func orderedUniqueAddresses(_ resolvers: [DNSResolver]) -> [String] {
        var seen = Set<String>()
        return resolvers.map(\.address).filter { seen.insert($0).inserted }
    }

    static func countryName(_ iso: String?) -> String? {
        guard let iso else { return nil }
        return Locale(identifier: "en_US").localizedString(forRegionCode: iso) ?? iso
    }
}
