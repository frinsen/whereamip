import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

final class MenuBuilderTests: XCTestCase {
    func vpnState() -> ExitState {
        ExitState(connectivity: .online,
                  exit: ExitInfo(ip: "185.107.56.123", countryCode: "NL", city: "Amsterdam",
                                 org: "M247 Europe SRL", provider: "ipwho.is", fetchedAt: Date()),
                  route: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "OpenVPN", hijackRoutePresent: false),
                  privateRelay: .active(egressIP: "172.224.224.5", egressCountry: "DE"),
                  since: Date())
    }
    func titles(_ menu: NSMenu) -> [String] { menu.items.map(\.title) }

    // Assertions here go through L10n rather than literals ON PURPOSE: retuning the
    // wording of a row is exactly what the extraction exists to allow, and a test that
    // pinned the prose would veto every such edit. What's actually asserted is
    // structure — which row, in what order, enabled or not, with which data
    // interpolated. `stem` serves the absence checks: the literal part of a format up
    // to its first placeholder is enough to recognise a row without pinning wording.
    func stem(_ key: L10nKey) -> String { String(L10n.string(key).prefix { $0 != "%" }) }

    func testMenuContainsEssentials() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: true, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains("185.107.56.123"))
        XCTAssertTrue(all.contains("Amsterdam"))
        XCTAssertTrue(all.contains("M247"))
        XCTAssertTrue(all.contains("OpenVPN"))
        XCTAssertTrue(all.contains(L10n.string(.menuPrivateRelay, L10n.string(.menuPrivateRelayVia, "🇩🇪"))))
        XCTAssertTrue(all.contains(L10n.string(.menuQuit)))
    }
    func testIPRowIsEnabledInfoRowsDisabled() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let ipItem = menu.items.first { $0.title.contains("185.107.56.123") }!
        XCTAssertTrue(ipItem.isEnabled)
        let cityItem = menu.items.first { $0.title.contains("Amsterdam") }!
        XCTAssertFalse(cityItem.isEnabled)
    }
    func testNoVPNMeansNoVPNRows() {
        var s = vpnState()
        s.route = RouteInfo(defaultInterface: "en0", isVPN: false, vpnName: nil, hijackRoutePresent: false)
        s.privateRelay = .inactive
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertFalse(all.contains(stem(.menuRouteVPN)))
        XCTAssertFalse(all.contains(stem(.menuPrivateRelay)))
    }
    func testNonVPNRouteShowsLinkKindRow() {
        var s = vpnState()
        s.route = RouteInfo(defaultInterface: "en0", isVPN: false, vpnName: nil,
                            hijackRoutePresent: false, linkKind: "Wi-Fi", linkName: "Wi-Fi")
        s.privateRelay = .inactive
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains(L10n.string(.menuRouteLink, "Wi-Fi", "en0")))
    }
    func testOfflineShowsLastSeen() {
        var s = vpnState()
        s.connectivity = .offline
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains(L10n.string(.menuOffline)))
        XCTAssertTrue(all.contains(stem(.menuOfflineLastSeen)))
    }
    func testLastSeenAndSinceShowFullDateAndTime() {
        // Locale-aware: build the expected fragment with the same formatter the
        // production code uses rather than hardcoding a locale-specific literal.
        let expected = MenuBuilder.timeFormatter.string(from: fixedDate)

        var offlineState = vpnState()
        offlineState.connectivity = .offline
        offlineState.exit = ExitInfo(ip: "185.107.56.123", countryCode: "NL", city: "Amsterdam",
                                     org: "M247 Europe SRL", provider: "ipwho.is", fetchedAt: fixedDate)
        let offlineMenu = MenuBuilder.build(state: offlineState, style: .emoji,
                                            notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let lastSeenItem = offlineMenu.items.first { $0.title.contains(stem(.menuOfflineLastSeen)) }!
        XCTAssertTrue(lastSeenItem.title.contains(expected))

        var onlineState = vpnState()
        onlineState.since = fixedDate
        let onlineMenu = MenuBuilder.build(state: onlineState, style: .emoji,
                                           notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let sinceItem = onlineMenu.items.first { $0.title.hasPrefix(stem(.menuSince)) }!
        XCTAssertTrue(sinceItem.title.contains(expected))
    }
    var fixedDate: Date { Date(timeIntervalSince1970: 1_700_000_000) }
    func testCheckedRowAbsentWhenLastCheckedNil() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.hasPrefix(stem(.menuChecked)) })
    }
    func testCheckedRowPresentDirectlyAfterSinceAndFormattedConsistently() {
        // Same formatter as Since — proves the two rows can't drift into two
        // different date formats over time (one source of truth).
        let checkedDate = Date(timeIntervalSince1970: 1_700_000_500)
        let expected = MenuBuilder.timeFormatter.string(from: checkedDate)

        var state = vpnState()
        state.since = fixedDate
        let menu = MenuBuilder.build(state: state, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     lastChecked: checkedDate, actions: MenuActions())
        let all = titles(menu)
        let sinceIndex = all.firstIndex { $0.hasPrefix(stem(.menuSince)) }!
        let checkedIndex = all.firstIndex { $0.hasPrefix(stem(.menuChecked)) }!
        XCTAssertEqual(checkedIndex, sinceIndex + 1)
        XCTAssertTrue(all[checkedIndex].contains(expected))
    }
    func testHijackWarningRow() {
        var s = vpnState()
        s.connectivity = .offline
        s.route.hijackRoutePresent = true
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(titles(menu).contains(L10n.string(.menuOfflineHijack)))
    }
    func testStyleRadioReflectsSelection() {
        let menu = MenuBuilder.build(state: vpnState(), style: .code,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let styleMenu = settings.items.first { $0.title == L10n.string(.settingsStyle) }!.submenu!
        XCTAssertEqual(styleMenu.items.first { $0.state == .on }?.title, L10n.string(.settingsStyleCode))
    }
    func testUpdateRowAppearsFirstWhenAvailable() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     availableUpdate: "0.3", actions: MenuActions())
        let first = menu.items.first!
        XCTAssertTrue(first.title.contains("0.3"))
        XCTAssertTrue(first.isEnabled)
    }
    func testNoUpdateRowWhenUnavailable() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains(stem(.menuUpdateAvailable)) })
    }
    func testRestartRowAppearsFirstWhenPresent() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     restartUpdate: "0.3.2", actions: MenuActions())
        let first = menu.items.first!
        XCTAssertEqual(first.title, L10n.string(.menuUpdateRestart, "0.3.2"))
        XCTAssertTrue(first.isEnabled)
    }
    func testRestartRowSupersedesAvailableUpdateRow() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     availableUpdate: "0.3.2", restartUpdate: "0.3.2", actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains(stem(.menuUpdateAvailable)) })
        let first = menu.items.first!
        XCTAssertTrue(first.title.contains(stem(.menuUpdateRestart)))
    }
    func testNoRestartRowWhenNil() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains(stem(.menuUpdateRestart)) })
    }
    func testGeneralRestartRowAlwaysPresentImmediatelyBeforeQuit() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let restartIndex = menu.items.firstIndex { $0.title == L10n.string(.menuRestart) }
        let quitIndex = menu.items.firstIndex { $0.title == L10n.string(.menuQuit) }
        XCTAssertNotNil(restartIndex)
        XCTAssertNotNil(quitIndex)
        XCTAssertEqual(restartIndex! + 1, quitIndex!)
        XCTAssertTrue(menu.items[restartIndex!].isEnabled)
    }
    func testHeaderShowsRunningVersion() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let header = menu.items.first { $0.title.contains(stem(.menuHeader)) }
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.title, L10n.string(.menuHeader, whereamipVersion))
    }
    func testHeaderShowsAppIconNotFlagEmoji() {
        // The exit-country flag emoji used to prefix this row — redundant,
        // since it's already the menu *bar* glyph directly above the
        // dropdown. Replaced with the app icon so the row identifies which
        // app the dropdown belongs to instead of repeating the flag.
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let header = menu.items.first { $0.title.contains(stem(.menuHeader)) }!
        XCTAssertEqual(header.title, L10n.string(.menuHeader, whereamipVersion))
        XCTAssertFalse(header.title.contains("🇳🇱"))
        XCTAssertFalse(header.title.contains("❓"))
        XCTAssertNotNil(header.image)
    }
    func testGeneralRestartRowStillPresentWhenUpdateRowsShown() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     restartUpdate: "0.3.2", actions: MenuActions())
        let restartIndex = menu.items.firstIndex { $0.title == L10n.string(.menuRestart) }
        let quitIndex = menu.items.firstIndex { $0.title == L10n.string(.menuQuit) }
        XCTAssertNotNil(restartIndex)
        XCTAssertEqual(restartIndex! + 1, quitIndex!)
    }
    func testAddToApplicationsFolderReflectsStateOn() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     applicationsLinked: true, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsApplicationsLink) }!
        XCTAssertEqual(item.state, .on)
    }
    func testAddToApplicationsFolderReflectsStateOff() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     applicationsLinked: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsApplicationsLink) }!
        XCTAssertEqual(item.state, .off)
    }
    func testAddToApplicationsFolderFiresAction() {
        var fired = false
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     actions: MenuActions(toggleApplicationsLink: { fired = true }))
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsApplicationsLink) }!
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(fired)
    }
    func testShowWelcomeWindowRowExistsAndFires() {
        var fired = false
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     actions: MenuActions(showWelcomeWindow: { fired = true }))
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsWelcome) }!
        XCTAssertEqual(item.state, .off)   // plain action, never a checkmark
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(fired)
    }
    func testNotificationsRowTitleAndStateReflectSetting() {
        // Harmonized on "Show Notifications" — a verb phrase like its
        // siblings (Launch at Login, Add to Applications folder, Check for
        // Updates) using System Settings' "Notifications" vocabulary for the
        // noun; detail lives in the welcome window's caption, not this menu
        // row. Was "Notify on changes".
        let onMenu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                       notificationsEnabled: true, launchAtLogin: false, actions: MenuActions())
        let settingsOn = onMenu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let onItem = settingsOn.items.first { $0.title == L10n.string(.settingsNotifications) }!
        XCTAssertEqual(onItem.state, .on)

        let offMenu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                        notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let settingsOff = offMenu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let offItem = settingsOff.items.first { $0.title == L10n.string(.settingsNotifications) }!
        XCTAssertEqual(offItem.state, .off)
    }
    func testCheckForUpdatesToggleReflectsSettingOn() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     updatesEnabled: true, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsUpdates) }!
        XCTAssertEqual(item.state, .on)
    }
    func testCheckForUpdatesToggleReflectsSettingOff() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     updatesEnabled: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }!.submenu!
        let item = settings.items.first { $0.title == L10n.string(.settingsUpdates) }!
        XCTAssertEqual(item.state, .off)
    }
    func testRendererEmoji() {
        let r = StatusItemRenderer.render(.text("🇩🇪"))
        XCTAssertEqual(r.title, "🇩🇪"); XCTAssertNil(r.image)
        let sym = StatusItemRenderer.render(.symbol("wifi.slash"))
        XCTAssertNil(sym.title); XCTAssertNotNil(sym.image); XCTAssertTrue(sym.image!.isTemplate)
    }
    // Flags asset bundle is available (added in Task 14), but codes without assets still
    // fall back to emoji. "zz" is a valid 2-letter code format but has no flagcdn asset,
    // so it must fall back to emoji (not the asset-present path). This tests the critical
    // behavior: assets when present, emoji when not, never nil+nil (which would be a
    // blank status item). Task 14 made the original "de" fixture invalid (asset now exists),
    // so we use "zz" (no asset) to preserve fallback-path coverage.
    func testRendererFlagImageFallsBackToEmojiWhenAssetMissing() {
        let noAsset = StatusItemRenderer.render(.flagImage(iso: "zz"))
        XCTAssertEqual(noAsset.title, "🇿🇿")   // Regional indicator emoji for ZZ
        XCTAssertNil(noAsset.image)
    }
    func testRendererFlagImageFallsBackToQuestionMarkForUnrecognizedISO() {
        // "123" fails Flags.emoji's 2-ASCII-letter validation, so the ultimate "?" default applies.
        let invalid = StatusItemRenderer.render(.flagImage(iso: "123"))
        XCTAssertEqual(invalid.title, "?")
        XCTAssertNil(invalid.image)
    }
    func testFlagAssetRendering() {
        let r = StatusItemRenderer.render(.flagImage(iso: "de"))
        XCTAssertNil(r.title)          // asset exists → image, not emoji fallback
        XCTAssertNotNil(r.image)
        XCTAssertFalse(r.image!.isTemplate)   // real flag colors, not template
        let fallback = StatusItemRenderer.render(.flagImage(iso: "zz"))
        XCTAssertNotNil(fallback.title)       // unknown asset → emoji/text fallback, never nil+nil
    }

    // MARK: - IPv6 leak

    func leakState() -> ExitState {
        var s = vpnState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "DE", city: "Berlin", org: "Deutsche Telekom",
                           provider: "ipwho.is", fetchedAt: Date())
        s.ipv6Leak = true
        return s
    }
    func testIPv6LeakWarningRowIsFirstInInfoArea() {
        let menu = MenuBuilder.build(state: leakState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let warningIndex = menu.items.firstIndex { $0.title.contains(stem(.menuLeakIPv6)) }
        XCTAssertNotNil(warningIndex)
        let ipIndex = menu.items.firstIndex { $0.title.contains("185.107.56.123") }
        XCTAssertNotNil(ipIndex)
        XCTAssertLessThan(warningIndex!, ipIndex!)
        let warningItem = menu.items[warningIndex!]
        XCTAssertFalse(warningItem.isEnabled)
        XCTAssertTrue(warningItem.title.contains("Deutsche Telekom"))
        XCTAssertTrue(warningItem.title.contains("DE"))
    }
    func testNoLeakWarningRowWhenNotLeaking() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains(stem(.menuLeakIPv6)) })
    }
    func testIPv4IPv6SplitLinesWhenCountriesDiffer() {
        var s = vpnState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: "DE", city: "Berlin", org: "Deutsche Telekom",
                           provider: "ipwho.is", fetchedAt: Date())
        // countries differ (NL vs DE) but not flagged as a confirmed leak here
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains("IPv4: 185.107.56.123"))
        XCTAssertTrue(all.contains("IPv6: 2001:db8::1"))
    }
    func testSplitLinesShownWhenSameCountry() {
        var s = vpnState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: s.exit!.countryCode, city: "Amsterdam",
                           org: "M247 Europe SRL", provider: "ipwho.is", fetchedAt: Date())
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        // IPv6 is now a first-class fact shown whenever measured, even if countries match
        XCTAssertTrue(all.contains("IPv4:"))
        XCTAssertTrue(all.contains("IPv6:"))
    }
    func testStatusRendererAppendsBadgeForTextGlyph() {
        let r = StatusItemRenderer.render(.text("🇩🇪"), warning: true)
        XCTAssertEqual(r.title, "🇩🇪 ⚠️")
        XCTAssertNil(r.image)
    }
    func testStatusRendererAppendsBadgeForFlagImage() {
        let r = StatusItemRenderer.render(.flagImage(iso: "de"), warning: true)
        XCTAssertNotNil(r.image)
        XCTAssertEqual(r.title, "⚠️")
    }
    func testStatusRendererNoBadgeWhenNotLeaking() {
        let r = StatusItemRenderer.render(.text("🇩🇪"), warning: false)
        XCTAssertEqual(r.title, "🇩🇪")
    }

    func testIPv6SplitLinesShownEvenWhenCountriesMatch() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.exit6 = ExitInfo(ip: "2a00::1", countryCode: "CZ", provider: "t", fetchedAt: Date())
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("IPv4: 1.2.3.4 (CZ)"), "got: \(titles)")
        XCTAssertTrue(titles.contains("IPv6: 2a00::1 (CZ)"))
    }

    func testSettingsSubmenuHasNoDuplicateVersionRow() {
        // The main dropdown header already shows "WhereAmIP v<version>" — the Settings
        // submenu must not brand itself with a second copy of it.
        let menu = MenuBuilder.build(state: ExitState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }?.submenu
        XCTAssertFalse(settings?.items.contains { $0.title == L10n.string(.menuHeader, whereamipVersion) } ?? true)
    }

    // MARK: - DNS

    func testHealthyDNSRowShown() {
        var state = ExitState(connectivity: .online)
        state.dns.resolvers = [DNSResolver(address: "10.8.0.1", isIPv6: false, interface: "utun13"),
                               DNSResolver(address: "9.9.9.9", isIPv6: false)]
        state.dns.encryption = .doh
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(menu.items.map(\.title).contains(L10n.string(.dnsRow, "10.8.0.1") + L10n.string(.dnsRowInterface, "utun13")
                                                  + L10n.string(.dnsRowDoH) + L10n.string(.dnsRowMore, 1)))
    }

    // Field bug: DNSConfigReader.parse deliberately dedups by (address, interface) — a global
    // entry plus one per-service entry — so the same address can appear up to 3x. The "+N more"
    // count must reflect UNIQUE addresses, not raw model entries.
    func testDNSMoreCountReflectsUniqueAddressesNotRawEntryCount() {
        var state = ExitState(connectivity: .online)
        // 4 unique addresses, 12 total entries (each repeated up to 3x across nil/en0/utun).
        let addresses = ["192.168.178.1", "fd00::1", "2001:db8::1", "2001:db8::2"]
        let interfaces: [String?] = [nil, "en0", "utun4"]
        state.dns.resolvers = addresses.flatMap { addr in
            interfaces.map { iface in DNSResolver(address: addr, isIPv6: addr.contains(":"), interface: iface) }
        }
        XCTAssertEqual(state.dns.resolvers.count, 12)
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let dnsRow = menu.items.map(\.title).first { $0.hasPrefix(L10n.string(.dnsRow, "192.168.178.1")) }
        XCTAssertEqual(dnsRow, L10n.string(.dnsRow, "192.168.178.1") + L10n.string(.dnsRowMore, 3))
    }

    func testDNSMoreSuffixOmittedWhenOnlyOneUniqueAddress() {
        var state = ExitState(connectivity: .online)
        // Same address repeated across three interfaces (dedup artifact) — only 1 unique address.
        state.dns.resolvers = [DNSResolver(address: "9.9.9.9", isIPv6: false),
                               DNSResolver(address: "9.9.9.9", isIPv6: false, interface: "en0"),
                               DNSResolver(address: "9.9.9.9", isIPv6: false, interface: "utun4")]
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let dnsRow = menu.items.map(\.title).first { $0.hasPrefix(L10n.string(.dnsRow, "9.9.9.9")) }
        XCTAssertEqual(dnsRow, L10n.string(.dnsRow, "9.9.9.9"))
    }

    func testDNSLeakWarningRowFirstAndBadgePredicate() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.dns.leak = .confirmed
        state.dns.egressIP = "203.0.113.7"
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(menu.items.map(\.title).contains(L10n.string(.menuLeakDNS, "203.0.113.7")))
        let (title, _) = StatusItemRenderer.render(.text("🇨🇿"), warning: true)
        XCTAssertEqual(title, "🇨🇿 ⚠️")
    }

    func testDNSLeakConfirmedRowShowsResolvedOperatorWhenPresent() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.dns.leak = .confirmed
        state.dns.egressIP = "203.0.113.7"
        state.dns.egressOrg = "Cloudflare, Inc."
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(menu.items.map(\.title).contains(
            L10n.string(.menuLeakDNSWithOperator, "Cloudflare, Inc.", "203.0.113.7")))
    }
    func testDNSLeakConfirmedRowFallsBackWhenOrgMissing() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.dns.leak = .confirmed
        state.dns.egressIP = "203.0.113.7"
        XCTAssertNil(state.dns.egressOrg)
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(menu.items.map(\.title).contains(L10n.string(.menuLeakDNS, "203.0.113.7")))
    }
    func testDNSSuspectedRowIsQuieter() {
        var state = ExitState(connectivity: .online)
        state.exit = ExitInfo(ip: "1.2.3.4", countryCode: "CZ", provider: "t", fetchedAt: Date())
        state.dns.leak = .suspected
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(menu.items.map(\.title).contains(L10n.string(.menuLeakDNSSuspected)))
    }

    // MARK: - DNS detail submenu

    func dnsState() -> ExitState {
        var state = ExitState(connectivity: .online)
        state.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false),
                               DNSResolver(address: "192.168.178.1", isIPv6: false, interface: "en0"),
                               DNSResolver(address: "10.2.0.1", isIPv6: false, interface: "utun4")]
        state.dns.egressResolvers = [
            EgressResolver(ip: "185.44.108.99", port: 39071, operatorName: "WoodyNet, Inc.",
                           location: "Berlin, State of Berlin, DE", transport: "UDP"),
            EgressResolver(ip: "2620:171:57:f003::244", operatorName: "WoodyNet, Inc."),
        ]
        state.dns.egressIP = "185.44.108.99"
        return state
    }
    func dnsSubmenu(_ state: ExitState, dnsProbeEnabled: Bool = true) -> NSMenu? {
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, dnsProbeEnabled: dnsProbeEnabled,
                                     actions: MenuActions())
        return menu.items.first { $0.title.hasPrefix(stem(.dnsRow)) }?.submenu
    }

    func testDNSRowKeepsItsSummaryTitleAndGainsASubmenu() {
        let menu = MenuBuilder.build(state: dnsState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let row = menu.items.first { $0.title.hasPrefix(stem(.dnsRow)) }
        XCTAssertEqual(row?.title, L10n.string(.dnsRow, "192.168.178.1") + L10n.string(.dnsRowMore, 1))
        XCTAssertNotNil(row?.submenu)
        XCTAssertTrue(row?.isEnabled ?? false, "a disabled parent row can never be opened")
    }
    func testDNSSubmenuListsEachUniqueConfiguredResolverOnceWithInterfaceAttribution() {
        let titles = dnsSubmenu(dnsState())?.items.map(\.title) ?? []
        XCTAssertEqual(titles.filter { $0.hasPrefix("192.168.178.1") }, [L10n.string(.dnsResolverInterfaces, "192.168.178.1", "en0")],
                       "the same address across a global and a scoped entry is one row")
        XCTAssertTrue(titles.contains(L10n.string(.dnsResolverInterfaces, "10.2.0.1", "utun4")), "got: \(titles)")
    }
    func testDNSSubmenuListsEveryDiscoveredEgressResolver() {
        let titles = dnsSubmenu(dnsState())?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("185.44.108.99 — WoodyNet, Inc. (Berlin, DE) · UDP"), "got: \(titles)")
        XCTAssertTrue(titles.contains("2620:171:57:f003::244 — WoodyNet, Inc."))
    }
    func testDNSSubmenuSectionsAreLabelledAndSeparated() {
        let sub = dnsSubmenu(dnsState())
        let titles = sub?.items.map(\.title) ?? []
        let configuredIndex = titles.firstIndex(of: L10n.string(.dnsSectionConfigured))
        let egressIndex = titles.firstIndex(of: L10n.string(.dnsSectionEgress))
        XCTAssertNotNil(configuredIndex)
        XCTAssertNotNil(egressIndex)
        XCTAssertLessThan(configuredIndex!, egressIndex!)
        XCTAssertTrue(sub!.items[(configuredIndex!)..<egressIndex!].contains { $0.isSeparatorItem })
        XCTAssertFalse(sub!.items[configuredIndex!].isEnabled, "section labels are info rows, not actions")
    }
    func testDNSSubmenuFallsBackToTheSingleEgressIPWhenEnumerationFoundNothing() {
        var state = dnsState()
        state.dns.egressResolvers = []
        state.dns.egressIP = "203.0.113.7"
        state.dns.egressOrg = "Cloudflare, Inc."
        let titles = dnsSubmenu(state)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("203.0.113.7 — Cloudflare, Inc."), "got: \(titles)")
    }
    func testDNSSubmenuShowsDisabledRowWhenProbingIsOff() {
        let titles = dnsSubmenu(dnsState(), dnsProbeEnabled: false)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains(L10n.string(.dnsDisabled)), "got: \(titles)")
        XCTAssertFalse(titles.contains { $0.hasPrefix("185.44.108.99") },
                       "an opted-out user is shown no egress measurement at all")
    }
    func testDNSSubmenuOmitsTheEgressSectionWhenNothingWasMeasuredYet() {
        var state = dnsState()
        state.dns.egressResolvers = []
        state.dns.egressIP = nil
        let titles = dnsSubmenu(state)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains(L10n.string(.dnsSectionConfigured)))
        XCTAssertFalse(titles.contains(L10n.string(.dnsSectionEgress)), "no dangling section label: \(titles)")
    }

    // MARK: - router-forwarding attribution row

    func testForwarderHintRowShownWhenARouterForwardsToAKnownProvider() {
        var state = dnsState()
        state.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false)]
        let titles = dnsSubmenu(state)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains(L10n.string(.dnsForwarder, "Quad9")),
                      "got: \(titles)")
    }
    func testForwarderHintRowAbsentWhenAPublicResolverIsConfiguredDirectly() {
        var state = dnsState()
        state.dns.resolvers = [DNSResolver(address: "9.9.9.9", isIPv6: false)]
        let titles = dnsSubmenu(state)?.items.map(\.title) ?? []
        XCTAssertFalse(titles.contains { $0.hasPrefix(stem(.dnsForwarder)) }, "got: \(titles)")
    }
    func testForwarderHintRowAbsentForAnUnattributableEgress() {
        var state = dnsState()
        state.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false)]
        state.dns.egressResolvers = [EgressResolver(ip: "62.109.121.1", operatorName: "Deutsche Telekom AG")]
        let titles = dnsSubmenu(state)?.items.map(\.title) ?? []
        XCTAssertFalse(titles.contains { $0.hasPrefix(stem(.dnsForwarder)) }, "got: \(titles)")
    }

    func testDNSProbeToggleRow() {
        var called = false
        let menu = MenuBuilder.build(state: ExitState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, dnsProbeEnabled: false,
                                     actions: MenuActions(toggleDNSProbe: { called = true }))
        let settings = menu.items.first { $0.title == L10n.string(.menuSettings) }?.submenu
        let row = settings?.items.first { $0.title == L10n.string(.settingsDNSProbe) }
        XCTAssertEqual(row?.state, .off)
        (row?.representedObject as? AnyObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        XCTAssertTrue(called)
    }

    // MARK: - copy actions: the exit-row alternate

    func dualStackState() -> ExitState {
        var state = vpnState()
        state.exit6 = ExitInfo(ip: "2a09:bac5:27cd:2a0::43:80", countryCode: "NL", city: "Amsterdam",
                               org: "M247 Europe SRL", provider: "ipwho.is", fetchedAt: Date())
        return state
    }

    func testExitIPRowIsUnchangedAndStillCopiesTheIPv4() {
        var fired = false
        let menu = MenuBuilder.build(state: dualStackState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(copyIP: { fired = true }))
        let item = menu.items.first { $0.title == "185.107.56.123" }!
        XCTAssertEqual(item.keyEquivalent, "c")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
        XCTAssertFalse(item.isAlternate)
        (item.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        XCTAssertTrue(fired)
    }

    func testAlternateExitRowSitsDirectlyAfterTheIPRowAndSharesItsKey() {
        let menu = MenuBuilder.build(state: dualStackState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let all = titles(menu)
        let ipIndex = all.firstIndex(of: "185.107.56.123")!
        let alternateIndex = all.firstIndex(of: L10n.string(.menuCopyExitBoth))!
        // Adjacency is not cosmetic: AppKit only treats an item as the alternate of
        // the one it directly follows, and only when both carry the same key.
        XCTAssertEqual(alternateIndex, ipIndex + 1)
        let alternate = menu.items[alternateIndex]
        XCTAssertTrue(alternate.isAlternate)
        XCTAssertEqual(alternate.keyEquivalent, menu.items[ipIndex].keyEquivalent)
        XCTAssertEqual(alternate.keyEquivalentModifierMask, [.command, .option])
        XCTAssertEqual(menu.items[ipIndex].keyEquivalentModifierMask, [.command])
    }

    func testAlternateExitRowCopiesBothAddressesAndNothingElse() {
        var payload: String?
        let menu = MenuBuilder.build(state: dualStackState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(copyText: { payload = $0 }))
        let alternate = menu.items.first { $0.title == L10n.string(.menuCopyExitBoth) }!
        (alternate.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        // Addresses only — no city, no operator, no "IPv4:"/"IPv6:" label prefix.
        XCTAssertEqual(payload, "185.107.56.123\n2a09:bac5:27cd:2a0::43:80")
    }

    func testNoAlternateExitRowWithoutAnIPv6Exit() {
        // An alternate promising two addresses while copying one is the bug this avoids.
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains(L10n.string(.menuCopyExitBoth)))
        XCTAssertFalse(menu.items.contains { $0.isAlternate })
    }

    // MARK: - copy diagnostics

    func testCopyDiagnosticsIsTheFirstRowOfTheBottomActionBlock() {
        let menu = MenuBuilder.build(state: dualStackState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions())
        let all = titles(menu)
        let diagnosticsIndex = all.firstIndex(of: L10n.string(.menuCopyDiagnostics))!
        XCTAssertEqual(all.firstIndex(of: L10n.string(.menuRefresh)), diagnosticsIndex + 1)
        XCTAssertTrue(menu.items[diagnosticsIndex - 1].isSeparatorItem)
        let item = menu.items[diagnosticsIndex]
        XCTAssertEqual(item.keyEquivalent, "c")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertTrue(item.isEnabled)
    }

    func testCopyDiagnosticsCopiesExactlyWhatTheReportRenders() {
        var payload: String?
        var state = dualStackState()
        state.since = fixedDate
        let checked = Date(timeIntervalSince1970: 1_700_000_500)
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, dnsProbeEnabled: false,
                                     lastChecked: checked, actions: MenuActions(copyText: { payload = $0 }))
        let item = menu.items.first { $0.title == L10n.string(.menuCopyDiagnostics) }!
        (item.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        // The dropdown's own "Checked" stamp and DNS-probe setting travel into the
        // report — a pasted report says what the menu said, opt-out included.
        XCTAssertEqual(payload, DiagnosticsReport.text(for: state, checked: checked, dnsProbeEnabled: false))
        XCTAssertTrue(payload!.contains("DNS check disabled"))
    }

    // MARK: - help row

    func testHelpRowSitsDirectlyAboveSettingsAndFires() {
        var fired = false
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(showHelpWindow: { fired = true }))
        let all = titles(menu)
        let helpIndex = all.firstIndex(of: L10n.string(.menuHelp))!
        XCTAssertEqual(all.firstIndex(of: L10n.string(.menuSettings)), helpIndex + 1)
        let item = menu.items[helpIndex]
        XCTAssertEqual(item.keyEquivalent, "?")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
        (item.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        XCTAssertTrue(fired)
    }

    // MARK: - DNS bulk copy rows

    func testDNSSubmenuCopyRowsCloseTheSubmenuAndCarryNoKeyEquivalents() {
        let sub = dnsSubmenu(dnsState())!
        let rows = sub.items.map(\.title)
        let configuredCopy = rows.firstIndex(of: L10n.string(.dnsCopyConfigured))!
        let answeringCopy = rows.firstIndex(of: L10n.string(.dnsCopyAnswering))!
        XCTAssertEqual(answeringCopy, configuredCopy + 1)
        XCTAssertEqual(answeringCopy, sub.items.count - 1, "copy rows close the submenu: \(rows)")
        XCTAssertTrue(sub.items[configuredCopy - 1].isSeparatorItem)
        // Deliberately dropped: the rows are visible in the submenu, and one more
        // ⌘-something would compete with the shortcuts on the main dropdown.
        XCTAssertEqual(sub.items[configuredCopy].keyEquivalent, "")
        XCTAssertEqual(sub.items[answeringCopy].keyEquivalent, "")
        XCTAssertTrue(sub.items[configuredCopy].isEnabled)
        XCTAssertTrue(sub.items[answeringCopy].isEnabled)
    }

    func testConfiguredResolverCopyIsBareAddressesOnePerLine() {
        var payload: String?
        let menu = MenuBuilder.build(state: dnsState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(copyText: { payload = $0 }))
        let sub = menu.items.first { $0.title.hasPrefix(stem(.dnsRow)) }!.submenu!
        let row = sub.items.first { $0.title == L10n.string(.dnsCopyConfigured) }!
        (row.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        // The ROW reads "192.168.178.1 — en0"; the PAYLOAD is the address alone, once.
        XCTAssertEqual(payload, "192.168.178.1\n10.2.0.1")
    }

    func testAnsweringResolverCopyStripsOperatorLocationAndTransport() {
        var payload: String?
        let menu = MenuBuilder.build(state: dnsState(), style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(copyText: { payload = $0 }))
        let sub = menu.items.first { $0.title.hasPrefix(stem(.dnsRow)) }!.submenu!
        let row = sub.items.first { $0.title == L10n.string(.dnsCopyAnswering) }!
        (row.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        XCTAssertEqual(payload, "185.44.108.99\n2620:171:57:f003::244")
    }

    func testAnsweringResolverCopyFallsBackToTheBeaconEgress() {
        var payload: String?
        var state = dnsState()
        state.dns.egressResolvers = []
        state.dns.egressIP = "203.0.113.7"
        let menu = MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                                     launchAtLogin: false, actions: MenuActions(copyText: { payload = $0 }))
        let sub = menu.items.first { $0.title.hasPrefix(stem(.dnsRow)) }!.submenu!
        let row = sub.items.first { $0.title == L10n.string(.dnsCopyAnswering) }!
        (row.representedObject as? NSObject)?.perform(#selector(ActionTarget.fire))
        XCTAssertEqual(payload, "203.0.113.7")
    }

    func testNoAnsweringCopyRowWhenTheProbeIsOffOrNothingAnswered() {
        let offRows = dnsSubmenu(dnsState(), dnsProbeEnabled: false)!.items.map(\.title)
        XCTAssertFalse(offRows.contains(L10n.string(.dnsCopyAnswering)), "got: \(offRows)")
        XCTAssertTrue(offRows.contains(L10n.string(.dnsCopyConfigured)), "the local half stays copyable")

        var state = dnsState()
        state.dns.egressResolvers = []
        state.dns.egressIP = nil
        let rows = dnsSubmenu(state)!.items.map(\.title)
        XCTAssertFalse(rows.contains(L10n.string(.dnsCopyAnswering)), "got: \(rows)")
    }

    func testNoConfiguredCopyRowWithoutConfiguredResolvers() {
        // No resolvers at all means no DNS row to open in the first place, so this
        // guard is exercised against the submenu builder directly.
        var state = dnsState()
        state.dns.resolvers = []
        let sub = MenuBuilder.dnsSubmenu(state: state, dnsProbeEnabled: true)
        XCTAssertFalse(sub.items.map(\.title).contains(L10n.string(.dnsCopyConfigured)))
    }
}
