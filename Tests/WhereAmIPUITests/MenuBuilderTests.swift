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
}
