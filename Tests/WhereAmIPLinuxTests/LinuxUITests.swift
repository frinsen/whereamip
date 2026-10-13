#if os(Linux)
import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI
@testable import WhereAmIPLinuxUI

/// Pins the language like the macOS UI tests do, so the host's own setting cannot leak in.
class EnglishPinnedTestCase: XCTestCase {
    private var saved: (() -> String)!
    override func setUp() {
        super.setUp()
        saved = L10n.languageSetting
        L10n.languageSetting = { "en" }
    }
    override func tearDown() {
        L10n.languageSetting = saved
        super.tearDown()
    }
}

final class MenuModelTests: EnglishPinnedTestCase {
    let since = Date(timeIntervalSince1970: 1_790_000_000)
    let exit = ExitInfo(ip: "203.0.113.7", countryCode: "DE", city: "Berlin", org: "Deutsche Telekom AG",
                        provider: "ipwho.is", fetchedAt: Date(timeIntervalSince1970: 1_790_000_000), asn: 3320)

    func onlineState(exit6: ExitInfo? = nil, vpn: Bool = false) -> ExitState {
        ExitState(connectivity: .online, exit: exit, exit6: exit6,
                  route: vpn ? RouteInfo(defaultInterface: "wg0", isVPN: true, vpnName: "Office")
                             : RouteInfo(defaultInterface: "wlp2s0", linkKind: "Wi-Fi", linkName: "Wi-Fi"),
                  dns: DNSInfo(resolvers: [DNSResolver(address: "192.168.178.1", isIPv6: false, interface: "wlp2s0")],
                               egressIP: "74.80.89.244",
                               egressResolvers: [EgressResolver(ip: "74.80.89.244", operatorName: "WoodyNet, Inc.",
                                                                location: "Berlin, State of Berlin, DE", transport: "UDP")]),
                  since: since)
    }

    func ids(_ items: [MenuItemModel]) -> [String] { items.map(\.id) }
    func item(_ id: String, in items: [MenuItemModel]) -> MenuItemModel? {
        for item in items {
            if item.id == id { return item }
            if case .submenu(let children) = item.kind, let hit = self.item(id, in: children) { return hit }
        }
        return nil
    }

    func testOnlineMenuMirrorsTheMacOSDropdownOrder() {
        let menu = MenuModelBuilder.build(.init(state: onlineState(), lastChecked: since))
        XCTAssertEqual(ids(menu), ["header", "sep.header", "ip", "place", "org", "since", "checked",
                                   "sep.block", "route", "dns",
                                   "sep.controls", "diagnostics", "refresh", "help", "settings", "restart", "quit"])
        XCTAssertEqual(item("header", in: menu)?.title, "WhereAmIP v\(whereamipVersion)")
        XCTAssertEqual(item("place", in: menu)?.title, "Berlin, Germany")
        XCTAssertEqual(item("route", in: menu)?.title, "Route: Wi-Fi (wlp2s0)")
        XCTAssertEqual(item("quit", in: menu)?.kind, .action(.quit))
    }

    func testTheIPRowCopiesTheIPAndTheBothRowOnlyExistsWithAnIPv6Exit() {
        let v4only = MenuModelBuilder.build(.init(state: onlineState()))
        XCTAssertEqual(item("ip", in: v4only)?.kind, .action(.copyText("203.0.113.7")))
        XCTAssertNil(item("ip.both", in: v4only))

        let exit6 = ExitInfo(ip: "2001:db8::7", countryCode: "DE", city: "Berlin", provider: "ipwho.is", fetchedAt: since)
        let dual = MenuModelBuilder.build(.init(state: onlineState(exit6: exit6)))
        XCTAssertEqual(item("ip.both", in: dual)?.kind, .action(.copyText("203.0.113.7\n2001:db8::7")))
        XCTAssertEqual(item("split6", in: dual)?.title, "IPv6: 2001:db8::7 (Berlin, DE)")
    }

    func testCopyDiagnosticsCarriesTheSharedReport() {
        let state = onlineState(vpn: true)
        let menu = MenuModelBuilder.build(.init(state: state, dnsProbeEnabled: true, lastChecked: since))
        XCTAssertEqual(item("diagnostics", in: menu)?.kind,
                       .action(.copyText(DiagnosticsReport.text(for: state, checked: since, dnsProbeEnabled: true))))
        XCTAssertEqual(item("route", in: menu)?.title, "VPN: Office (wg0) owns default route")
    }

    func testOfflineShowsWhyAndNoCopyRow() {
        var state = onlineState()
        state.connectivity = .offline
        state.route.hijackRoutePresent = true
        let menu = MenuModelBuilder.build(.init(state: state))
        XCTAssertEqual(Array(ids(menu).prefix(3)), ["offline", "offline.hijack", "offline.lastSeen"])
        XCTAssertNil(item("ip", in: menu))
    }

    func testLeakWarningsComeFirstAndOnlyWhileOnline() {
        var state = onlineState(vpn: true)
        state.ipv6Leak = true
        state.exit6 = ExitInfo(ip: "2001:db8::7", countryCode: "DE", org: "Deutsche Telekom AG", provider: "ipwho.is", fetchedAt: since)
        state.dns.leak = .confirmed
        state.dns.egressOrg = "WoodyNet, Inc."
        let menu = MenuModelBuilder.build(.init(state: state))
        XCTAssertEqual(Array(ids(menu).prefix(4)), ["header", "sep.header", "leak.ipv6", "leak.dns"])
        XCTAssertEqual(item("leak.dns", in: menu)?.title, "⚠️ DNS leak — queries answered via WoodyNet, Inc. (74.80.89.244)")

        state.connectivity = .offline
        let offline = MenuModelBuilder.build(.init(state: state))
        XCTAssertNil(item("leak.ipv6", in: offline))
        XCTAssertNil(item("leak.dns", in: offline))
    }

    func testTheUpdateRowFitsTheInstallChannel() {
        let direct = MenuModelBuilder.build(.init(state: onlineState(), availableUpdate: "0.7", installChannel: .direct))
        XCTAssertEqual(item("update", in: direct)?.kind, .action(.openURL(UpdateChecker.releasesURL)))
        let brew = MenuModelBuilder.build(.init(state: onlineState(), availableUpdate: "0.7", installChannel: .homebrew))
        XCTAssertEqual(item("update", in: brew)?.kind, .action(.copyText("brew update && brew upgrade whereamip")))
        let restart = MenuModelBuilder.build(.init(state: onlineState(), availableUpdate: "0.7", restartUpdate: "0.7"))
        XCTAssertEqual(item("update", in: restart)?.kind, .action(.restartToUpdate))
    }

    func testTheDNSSubmenuHasBothSectionsAndBareAddressCopies() throws {
        let menu = MenuModelBuilder.build(.init(state: onlineState()))
        let dns = try XCTUnwrap(item("dns", in: menu))
        guard case .submenu(let rows) = dns.kind else { return XCTFail("DNS row is not a submenu") }
        XCTAssertEqual(rows.first?.title, "Configured resolvers")
        XCTAssertTrue(rows.contains { $0.title == "192.168.178.1 — wlp2s0" })
        XCTAssertTrue(rows.contains { $0.title == "74.80.89.244 — WoodyNet, Inc. (Berlin, DE) · UDP" })
        XCTAssertEqual(item("dns.copy.answering", in: rows)?.kind, .action(.copyText("74.80.89.244")))

        let disabled = MenuModelBuilder.build(.init(state: onlineState(), dnsProbeEnabled: false))
        guard case .submenu(let off)? = item("dns", in: disabled)?.kind else { return XCTFail() }
        XCTAssertTrue(off.contains { $0.title == "DNS check disabled" })
        XCTAssertNil(item("dns.copy.answering", in: off))
    }

    func testSettingsShowTheLinuxIntegrationsAndTheirState() {
        let menu = MenuModelBuilder.build(.init(state: onlineState(), style: .code, notificationsEnabled: true,
                                                launchAtLogin: false, launcherEntry: true, language: "de"))
        XCTAssertEqual(item("style.code", in: menu)?.kind, .toggle(isOn: true, radio: true, action: .setStyle(.code)))
        XCTAssertEqual(item("style.emoji", in: menu)?.kind, .toggle(isOn: false, radio: true, action: .setStyle(.emoji)))
        XCTAssertEqual(item("language.de", in: menu)?.kind, .toggle(isOn: true, radio: true, action: .setLanguage("de")))
        XCTAssertEqual(item("launcherEntry", in: menu)?.title, "Show in Applications Menu")
        XCTAssertEqual(item("launcherEntry", in: menu)?.kind, .toggle(isOn: true, radio: false, action: .toggleLauncherEntry))
        XCTAssertEqual(item("launchAtLogin", in: menu)?.kind, .toggle(isOn: false, radio: false, action: .toggleLaunchAtLogin))
        XCTAssertNil(item("whatsNew", in: menu))
    }

    /// What lets an open menu be updated in place: the ticking "Checked" stamp and a new IP
    /// change text, not shape — while a row appearing does change shape.
    func testStructureIgnoresTextButNotRows() {
        let a = MenuModelBuilder.build(.init(state: onlineState(), lastChecked: since))
        var moved = onlineState()
        moved.exit?.ip = "198.51.100.1"
        let b = MenuModelBuilder.build(.init(state: moved, lastChecked: since.addingTimeInterval(30)))
        XCTAssertEqual(a.structure, b.structure)
        XCTAssertNotEqual(a, b)
        let c = MenuModelBuilder.build(.init(state: onlineState(), availableUpdate: "9.9", lastChecked: since))
        XCTAssertNotEqual(a.structure, c.structure)
    }

    func testRowsFollowTheLanguageOverride() {
        L10n.languageSetting = { "de" }
        let menu = MenuModelBuilder.build(.init(state: onlineState()))
        XCTAssertEqual(item("refresh", in: menu)?.title, "Aktualisieren")
        XCTAssertEqual(item("launcherEntry", in: menu)?.title, "Im Anwendungsmenü anzeigen")
    }
}

final class PanelIconTests: XCTestCase {
    func state(_ connectivity: Connectivity, country: String? = "NL") -> ExitState {
        ExitState(connectivity: connectivity,
                  exit: country.map { ExitInfo(ip: "1.2.3.4", countryCode: $0, provider: "ipwho.is", fetchedAt: Date()) })
    }

    func testTheGlyphDecisionIsTheMacOSOne() {
        XCTAssertEqual(PanelIcon.forState(state(.online), style: .image).content, .flag(iso: "nl"))
        XCTAssertEqual(PanelIcon.forState(state(.online), style: .code).content, .text("NL"))
        XCTAssertEqual(PanelIcon.forState(state(.online), style: .emoji).content, .text("🇳🇱"))
        XCTAssertEqual(PanelIcon.forState(state(.offline), style: .image).content, .offline)
        XCTAssertEqual(PanelIcon.forState(state(.online, country: nil), style: .image).content, .unknown)
    }

    func testTheWarningBadgeFollowsConfirmedLeaksOnly() {
        var leaking = state(.online)
        leaking.dns.leak = .suspected
        XCTAssertFalse(PanelIcon.forState(leaking, style: .code).warning)
        leaking.dns.leak = .confirmed
        XCTAssertTrue(PanelIcon.forState(leaking, style: .code).warning)
        var v6 = state(.online)
        v6.ipv6Leak = true
        XCTAssertTrue(PanelIcon.forState(v6, style: .code).warning)
    }

    func testFileNamesAreAFunctionOfThePixels() {
        let names = [PanelIcon(content: .flag(iso: "de")), PanelIcon(content: .flag(iso: "de"), warning: true),
                     PanelIcon(content: .flag(iso: "de"), dimmed: true), PanelIcon(content: .text("DE")),
                     PanelIcon(content: .text("🇩🇪")), PanelIcon(content: .offline), PanelIcon(content: .unknown)]
            .map(\.fileStem)
        XCTAssertEqual(Set(names).count, names.count, "\(names)")
        XCTAssertEqual(PanelIcon(content: .text("🇩🇪")).fileStem, "whereamip-text-1f1e9-1f1ea")
        for name in names {
            XCTAssertTrue(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, name)
        }
        XCTAssertEqual(PanelIcon(content: .flag(iso: "../../x")).fileStem, "whereamip-flag-x")
    }
}

final class PangoMarkupTests: XCTestCase {
    func testInlineMarkup() {
        XCTAssertEqual(PangoMarkup.inline("a **bold** and *it* `x<y`"), "a <b>bold</b> and <i>it</i> <tt>x&lt;y</tt>")
        XCTAssertEqual(PangoMarkup.inline("[the repo](https://github.com/frinsen/whereamip)"),
                       "<a href=\"https://github.com/frinsen/whereamip\">the repo</a>")
        XCTAssertEqual(PangoMarkup.inline("[not a link](javascript:x)"), "[not a link](javascript:x)")
        XCTAssertEqual(PangoMarkup.inline("Tom & Jerry <3"), "Tom &amp; Jerry &lt;3")
        XCTAssertEqual(PangoMarkup.inline("**unclosed"), "<b>unclosed</b>")
    }

    func testBlocksBecomeParagraphsAndBullets() {
        XCTAssertEqual(PangoMarkup.render(markdown: "**Title**\n\nSome\nwrapped text.\n\n- one\n- two"),
                       "<b>Title</b>\n\nSome wrapped text.\n\n• one\n\n• two")
    }

    /// GTK rejects a whole label over one malformed tag, which would leave a blank window.
    func testEveryBundledLinuxDocumentIsWellFormedMarkup() {
        for languages in [["en"], ["de"]] {
            for markdown in [LinuxContent.helpMarkdown(preferredLanguages: languages),
                             LinuxContent.welcomeMarkdown(preferredLanguages: languages)] {
                let markup = PangoMarkup.render(markdown: markdown)
                XCTAssertTrue(Self.isWellFormed(markup), "malformed markup for \(languages)")
                XCTAssertFalse(markup.contains("**"))
            }
        }
    }

    static func isWellFormed(_ markup: String) -> Bool {
        var stack: [String] = []
        var rest = Substring(markup)
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else { return false }
            let tag = rest[rest.index(after: open)..<close]
            if tag.hasPrefix("/") {
                guard stack.popLast() == String(tag.dropFirst()) else { return false }
            } else {
                stack.append(String(tag.prefix { $0 != " " }))
            }
            rest = rest[rest.index(after: close)...]
        }
        return stack.isEmpty
    }
}

final class LinuxContentTests: XCTestCase {
    func testHelpIsBundledInEveryLocaleAndExplainsTheLinuxSpecifics() {
        for (locale, topics) in [("en", ["NetworkManager", "AppIconTray", "whereamip debug", "Copy Diagnostics"]),
                                 ("de", ["NetworkManager", "AppIconTray", "whereamip debug", "Diagnose kopieren"])] {
            let help = LinuxContent.helpMarkdown(preferredLanguages: [locale])
            XCTAssertNotEqual(help, LinuxContent.helpFallback)
            for topic in topics { XCTAssertTrue(help.contains(topic), "\(locale) help never mentions \(topic)") }
            XCTAssertFalse(help.contains("⌘"), "\(locale) help still promises macOS shortcuts")
        }
    }

    func testWelcomeCopyIsThePanelVersionInEveryLocale() {
        XCTAssertTrue(LinuxContent.welcomeMarkdown(preferredLanguages: ["en"]).contains("panel"))
        XCTAssertTrue(LinuxContent.welcomeMarkdown(preferredLanguages: ["de-AT"]).contains("Panel"))
        XCTAssertEqual(LinuxContent.welcomeMarkdown(preferredLanguages: ["fr"]),
                       LinuxContent.welcomeMarkdown(preferredLanguages: ["en"]))
    }

    func testTheWelcomeWindowOpensOnTheFirstRunOnly() {
        XCTAssertTrue(LinuxContent.shouldShowWelcome(storedMilestone: ""))
        XCTAssertFalse(LinuxContent.shouldShowWelcome(storedMilestone: "0.1"))
    }

    func testFlagImagesResolveFromTheSharedBundleAndNothingElseDoes() {
        XCTAssertNotNil(LinuxContent.flagImageURL(iso: "de"))
        XCTAssertNil(LinuxContent.flagImageURL(iso: "zz"))
        XCTAssertNil(LinuxContent.flagImageURL(iso: "../x"))
        XCTAssertNil(LinuxContent.flagImageURL(iso: "DE"))
    }
}
#endif
