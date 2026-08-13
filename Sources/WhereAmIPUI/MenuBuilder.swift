import AppKit
import WhereAmIPCore

public struct MenuActions {
    public var copyIP: () -> Void
    public var refresh: () -> Void
    public var setStyle: (MenuBarStyle) -> Void
    public var toggleNotifications: () -> Void
    public var toggleLaunchAtLogin: () -> Void
    public var quit: () -> Void
    public init(copyIP: @escaping () -> Void = {}, refresh: @escaping () -> Void = {},
                setStyle: @escaping (MenuBarStyle) -> Void = { _ in },
                toggleNotifications: @escaping () -> Void = {},
                toggleLaunchAtLogin: @escaping () -> Void = {},
                quit: @escaping () -> Void = {}) {
        self.copyIP = copyIP; self.refresh = refresh; self.setStyle = setStyle
        self.toggleNotifications = toggleNotifications
        self.toggleLaunchAtLogin = toggleLaunchAtLogin; self.quit = quit
    }
}

/// Target object holding closures so NSMenuItem actions can call them.
final class ActionTarget: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

public enum MenuBuilder {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
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
                             actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

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
            menu.addItem(info("\(flag)  WhereAmIP"))
            menu.addItem(.separator())
            if let exit = state.exit {
                let ipItem = action(exit.ip, key: "c") { actions.copyIP() }
                ipItem.keyEquivalentModifierMask = [.command]
                menu.addItem(ipItem)
                let place = [exit.city, countryName(exit.countryCode)].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { menu.addItem(info(place)) }
                if let org = exit.org { menu.addItem(info(org)) }
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
        let notify = action("Notify on changes") { actions.toggleNotifications() }
        notify.state = notificationsEnabled ? .on : .off
        settingsMenu.addItem(notify)
        let login = action("Launch at Login") { actions.toggleLaunchAtLogin() }
        login.state = launchAtLogin ? .on : .off
        settingsMenu.addItem(login)
        settings.submenu = settingsMenu
        menu.addItem(settings)

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
