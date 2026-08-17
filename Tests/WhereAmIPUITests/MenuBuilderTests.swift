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

    func testMenuContainsEssentials() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: true, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains("185.107.56.123"))
        XCTAssertTrue(all.contains("Amsterdam"))
        XCTAssertTrue(all.contains("M247"))
        XCTAssertTrue(all.contains("OpenVPN"))
        XCTAssertTrue(all.contains("Private Relay"))
        XCTAssertTrue(all.contains("Quit WhereAmIP"))
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
        XCTAssertFalse(all.contains("VPN"))
        XCTAssertFalse(all.contains("Private Relay"))
    }
    func testOfflineShowsLastSeen() {
        var s = vpnState()
        s.connectivity = .offline
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertTrue(all.contains("No internet connection"))
        XCTAssertTrue(all.contains("Last seen"))
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
        let lastSeenItem = offlineMenu.items.first { $0.title.contains("Last seen online") }!
        XCTAssertTrue(lastSeenItem.title.contains(expected))

        var onlineState = vpnState()
        onlineState.since = fixedDate
        let onlineMenu = MenuBuilder.build(state: onlineState, style: .emoji,
                                           notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let sinceItem = onlineMenu.items.first { $0.title.hasPrefix("Since ") }!
        XCTAssertTrue(sinceItem.title.contains(expected))
    }
    var fixedDate: Date { Date(timeIntervalSince1970: 1_700_000_000) }
    func testHijackWarningRow() {
        var s = vpnState()
        s.connectivity = .offline
        s.route.hijackRoutePresent = true
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertTrue(titles(menu).joined(separator: "|").contains("hijack"))
    }
    func testStyleRadioReflectsSelection() {
        let menu = MenuBuilder.build(state: vpnState(), style: .code,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let styleMenu = settings.items.first { $0.title == "Menu Bar Style" }!.submenu!
        XCTAssertEqual(styleMenu.items.first { $0.state == .on }?.title, "ISO country code")
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
        XCTAssertFalse(titles(menu).contains { $0.contains("Update") })
    }
    func testRestartRowAppearsFirstWhenPresent() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     restartUpdate: "0.3.2", actions: MenuActions())
        let first = menu.items.first!
        XCTAssertTrue(first.title.contains("Restart to finish update"))
        XCTAssertTrue(first.title.contains("0.3.2"))
        XCTAssertTrue(first.isEnabled)
    }
    func testRestartRowSupersedesAvailableUpdateRow() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     availableUpdate: "0.3.2", restartUpdate: "0.3.2", actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains("Update v") })
        let first = menu.items.first!
        XCTAssertTrue(first.title.contains("Restart to finish update"))
    }
    func testNoRestartRowWhenNil() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        XCTAssertFalse(titles(menu).contains { $0.contains("Restart to finish update") })
    }
    func testGeneralRestartRowAlwaysPresentImmediatelyBeforeQuit() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let restartIndex = menu.items.firstIndex { $0.title == "Restart WhereAmIP" }
        let quitIndex = menu.items.firstIndex { $0.title == "Quit WhereAmIP" }
        XCTAssertNotNil(restartIndex)
        XCTAssertNotNil(quitIndex)
        XCTAssertEqual(restartIndex! + 1, quitIndex!)
        XCTAssertTrue(menu.items[restartIndex!].isEnabled)
    }
    func testHeaderShowsRunningVersion() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let header = menu.items.first { $0.title.contains("WhereAmIP v") }
        XCTAssertNotNil(header)
        XCTAssertTrue(header!.title.contains("v\(whereamipVersion)"))
    }
    func testGeneralRestartRowStillPresentWhenUpdateRowsShown() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     restartUpdate: "0.3.2", actions: MenuActions())
        let restartIndex = menu.items.firstIndex { $0.title == "Restart WhereAmIP" }
        let quitIndex = menu.items.firstIndex { $0.title == "Quit WhereAmIP" }
        XCTAssertNotNil(restartIndex)
        XCTAssertEqual(restartIndex! + 1, quitIndex!)
    }
    func testAddToApplicationsFolderReflectsStateOn() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     applicationsLinked: true, actions: MenuActions())
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Add to Applications folder" }!
        XCTAssertEqual(item.state, .on)
    }
    func testAddToApplicationsFolderReflectsStateOff() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     applicationsLinked: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Add to Applications folder" }!
        XCTAssertEqual(item.state, .off)
    }
    func testAddToApplicationsFolderFiresAction() {
        var fired = false
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     actions: MenuActions(toggleApplicationsLink: { fired = true }))
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Add to Applications folder" }!
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(fired)
    }
    func testShowWelcomeWindowRowExistsAndFires() {
        var fired = false
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     actions: MenuActions(showWelcomeWindow: { fired = true }))
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Show Welcome Window" }!
        XCTAssertEqual(item.state, .off)   // plain action, never a checkmark
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(fired)
    }
    func testCheckForUpdatesToggleReflectsSettingOn() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     updatesEnabled: true, actions: MenuActions())
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Check for Updates" }!
        XCTAssertEqual(item.state, .on)
    }
    func testCheckForUpdatesToggleReflectsSettingOff() {
        let menu = MenuBuilder.build(state: vpnState(), style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false,
                                     updatesEnabled: false, actions: MenuActions())
        let settings = menu.items.first { $0.title == "Settings" }!.submenu!
        let item = settings.items.first { $0.title == "Check for Updates" }!
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
        let warningIndex = menu.items.firstIndex { $0.title.contains("⚠️ IPv6 leak") }
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
        XCTAssertFalse(titles(menu).contains { $0.contains("IPv6 leak") })
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
    func testNoSplitLinesWhenSameCountry() {
        var s = vpnState()
        s.exit6 = ExitInfo(ip: "2001:db8::1", countryCode: s.exit!.countryCode, city: "Amsterdam",
                           org: "M247 Europe SRL", provider: "ipwho.is", fetchedAt: Date())
        let menu = MenuBuilder.build(state: s, style: .emoji,
                                     notificationsEnabled: false, launchAtLogin: false, actions: MenuActions())
        let all = titles(menu).joined(separator: "|")
        XCTAssertFalse(all.contains("IPv4:"))
        XCTAssertFalse(all.contains("IPv6:"))
    }
    func testStatusRendererAppendsBadgeForTextGlyph() {
        let r = StatusItemRenderer.render(.text("🇩🇪"), ipv6Leak: true)
        XCTAssertEqual(r.title, "🇩🇪 ⚠️")
        XCTAssertNil(r.image)
    }
    func testStatusRendererAppendsBadgeForFlagImage() {
        let r = StatusItemRenderer.render(.flagImage(iso: "de"), ipv6Leak: true)
        XCTAssertNotNil(r.image)
        XCTAssertEqual(r.title, "⚠️")
    }
    func testStatusRendererNoBadgeWhenNotLeaking() {
        let r = StatusItemRenderer.render(.text("🇩🇪"), ipv6Leak: false)
        XCTAssertEqual(r.title, "🇩🇪")
    }
}
