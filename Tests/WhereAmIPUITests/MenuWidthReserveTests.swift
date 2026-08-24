import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The width half of the ⌥ flicker fix.
///
/// The key-equivalent column sizes to its widest VISIBLE entry, so revealing the ⌥⌘C
/// alternate widened the whole panel by the ⌥ glyph (measured: 14pt) — and a status-item
/// menu is right-anchored, so the left edge jumped outward. The build reserves the wider
/// state up front; these tests pin that the floor exists, covers the alternate, and is not
/// applied to menus that cannot change width.
final class MenuWidthReserveTests: XCTestCase {
    func dualStackState() -> ExitState {
        var state = ExitState(connectivity: .online,
                              exit: ExitInfo(ip: "185.107.56.123", countryCode: "NL", city: "Amsterdam",
                                             org: "M247", provider: "ipwho.is", fetchedAt: Date()),
                              route: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "OpenVPN"),
                              since: Date())
        state.exit6 = ExitInfo(ip: "2a09:bac5:27cd:2a0::43:80", countryCode: "NL",
                               provider: "ipwho.is", fetchedAt: Date())
        return state
    }
    func build(_ state: ExitState) -> NSMenu {
        MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                          launchAtLogin: false, actions: MenuActions())
    }

    /// The reservation must cover the state where the alternate is the visible row —
    /// demonstrated by showing it also covers the menu once the alternate is gone, i.e. it
    /// is a ceiling over both modifier states rather than a snapshot of the resting one.
    func testAMenuWithAnAlternateReservesAWidthCoveringBothModifierStates() throws {
        let menu = build(dualStackState())
        let reserved = menu.minimumWidth
        XCTAssertGreaterThan(reserved, 0, "no width was reserved, so ⌥ can still resize the menu")
        XCTAssertEqual(reserved, menu.size.width, accuracy: 0.5,
                       "the floor must be the menu's own natural width, not a guess")

        // Strip the alternates: what remains is the resting state's requirement.
        menu.items.filter(\.isAlternate).forEach { menu.removeItem($0) }
        XCTAssertLessThanOrEqual(menu.size.width, reserved,
                                 "the resting state must already fit inside the reservation")
    }

    /// Deliberately wide alternate: the reservation has to follow the CONTENT, which is what
    /// makes this locale-proof rather than a hardcoded glyph allowance.
    func testTheReservationGrowsWithAWiderAlternate() {
        let narrow = NSMenu()
        let a = NSMenuItem(title: "1.2.3.4", action: nil, keyEquivalent: "c")
        a.keyEquivalentModifierMask = [.command]
        narrow.addItem(a)
        let b = NSMenuItem(title: "Copy both", action: nil, keyEquivalent: "c")
        b.keyEquivalentModifierMask = [.command, .option]
        b.isAlternate = true
        narrow.addItem(b)
        MenuBuilder.reserveAlternateWidth(narrow)

        let wide = NSMenu()
        let c = NSMenuItem(title: "1.2.3.4", action: nil, keyEquivalent: "c")
        c.keyEquivalentModifierMask = [.command]
        wide.addItem(c)
        let d = NSMenuItem(title: "Copy both exit addresses, a considerably longer label",
                           action: nil, keyEquivalent: "c")
        d.keyEquivalentModifierMask = [.command, .option]
        d.isAlternate = true
        wide.addItem(d)
        MenuBuilder.reserveAlternateWidth(wide)

        XCTAssertGreaterThan(wide.minimumWidth, narrow.minimumWidth)
    }

    func testAMenuWithoutAlternatesIsLeftAlone() {
        // Offline: no exit row, so no alternate — and nothing that can change width mid-open.
        var offline = dualStackState()
        offline.connectivity = .offline
        let menu = build(offline)
        XCTAssertFalse(menu.items.contains(where: \.isAlternate))
        XCTAssertEqual(menu.minimumWidth, 0, "menus that can't change width must not be pinned")

        // The DNS submenu is the other alternate-free menu the builder produces.
        var dns = dualStackState()
        dns.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false, interface: "en0")]
        let submenu = MenuBuilder.dnsSubmenu(state: dns, dnsProbeEnabled: true)
        XCTAssertEqual(submenu.minimumWidth, 0)
    }

    /// Measuring must not disturb what it measures: every alternate is still an alternate
    /// afterwards, or ⌥ would stop swapping and both rows would show at once.
    func testMeasuringLeavesEveryAlternateFlagIntact() throws {
        let menu = build(dualStackState())
        let alternates = menu.items.filter(\.isAlternate)
        XCTAssertEqual(alternates.count, 1)
        XCTAssertEqual(try XCTUnwrap(alternates.first).title, L10n.string(.menuCopyExitBoth))
        // And it is still adjacent to the row it alternates with.
        let ipIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "185.107.56.123" })
        XCTAssertTrue(menu.items[ipIndex + 1].isAlternate)
    }

    /// The reservation lives on the MENU, and the delegate moves only ITEMS into the
    /// long-lived status-item menu — so without explicit propagation the fix would be
    /// dropped on the way to the screen and the jump would survive.
    func testTheReservationSurvivesTheTransferIntoTheRealMenu() {
        let session = MenuTrackingSession()
        let target = NSMenu()
        session.updateIfNeeded(target) { self.build(self.dualStackState()) }
        XCTAssertGreaterThan(target.minimumWidth, 0, "the width reservation never reached the real menu")
    }

    /// The target menu outlives every build, so a later state needing no reservation has to
    /// clear it — otherwise the menu keeps the widest width it ever showed this session.
    func testALaterBuildWithoutAlternatesClearsTheReservation() {
        let session = MenuTrackingSession()
        let target = NSMenu()
        session.updateIfNeeded(target) { self.build(self.dualStackState()) }
        XCTAssertGreaterThan(target.minimumWidth, 0)

        var offline = dualStackState()
        offline.connectivity = .offline
        session.trackingEnded()
        session.updateIfNeeded(target) { self.build(offline) }
        XCTAssertEqual(target.minimumWidth, 0, "a stale reservation would leave the menu too wide")
    }
}
