import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The build-once-per-tracking-session guard behind the dropdown's ⌥ flicker fix.
///
/// AppKit calls `menuNeedsUpdate` on every keydown during menu tracking — modifier
/// presses included, because that is when it re-evaluates dynamic items. Rebuilding the
/// whole item tree there tears ~20 live views out of an OPEN menu on every ⌥ press and
/// release, which is what the user sees jump. The alternate pair needs no rebuild at all:
/// AppKit swaps it natively from the modifier state.
///
/// This is the extracted, testable half of `AppDelegate.menuNeedsUpdate` — identity
/// assertions here are the point, since equal-looking-but-new items are exactly the bug.
final class MenuTrackingSessionTests: XCTestCase {
    func state(ip: String = "185.107.56.123") -> ExitState {
        ExitState(connectivity: .online,
                  exit: ExitInfo(ip: ip, countryCode: "NL", city: "Amsterdam", org: "M247",
                                 provider: "ipwho.is", fetchedAt: Date()),
                  route: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "OpenVPN"),
                  since: Date())
    }
    func build(_ state: ExitState) -> NSMenu {
        MenuBuilder.build(state: state, style: .emoji, notificationsEnabled: false,
                          launchAtLogin: false, actions: MenuActions())
    }

    func testSecondUpdateInTheSameSessionLeavesTheItemTreeUntouched() {
        let session = MenuTrackingSession()
        let menu = NSMenu()
        var builds = 0
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }
        let first = menu.items
        XCTAssertFalse(first.isEmpty)

        // Every ⌥ press and release lands here while the menu is open.
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }

        XCTAssertEqual(builds, 1, "the menu must be built once per tracking session")
        XCTAssertEqual(menu.items.count, first.count)
        for (before, after) in zip(first, menu.items) {
            XCTAssertTrue(before === after, "item was replaced mid-session: \(after.title)")
        }
    }

    func testNextOpenAfterTrackingEndedRebuilds() {
        let session = MenuTrackingSession()
        let menu = NSMenu()
        var builds = 0
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }
        let first = menu.items

        session.trackingEnded()
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }

        XCTAssertEqual(builds, 2)
        XCTAssertEqual(menu.items.count, first.count)
        XCTAssertFalse(zip(first, menu.items).contains { $0 === $1 },
                       "a new tracking session must get freshly built items")
    }

    /// The behaviour the once-per-open rule must not cost us: what the menu shows is still
    /// current as of the moment it opens.
    func testAStateChangeBetweenSessionsIsPickedUpOnTheNextOpen() {
        let session = MenuTrackingSession()
        let menu = NSMenu()
        session.updateIfNeeded(menu) { build(state(ip: "1.1.1.1")) }
        XCTAssertTrue(menu.items.contains { $0.title == "1.1.1.1" })

        session.trackingEnded()
        session.updateIfNeeded(menu) { build(state(ip: "2.2.2.2")) }
        XCTAssertTrue(menu.items.contains { $0.title == "2.2.2.2" })
        XCTAssertFalse(menu.items.contains { $0.title == "1.1.1.1" })
    }

    /// `menuDidClose` can arrive for a menu that was never built (AppKit opens and closes a
    /// menu with no keydown, or the session object outlives a cancelled open), and an item
    /// action may fire around it — clearing the flag must be safe in any order, and must
    /// never leave a session stuck in "already built".
    func testTrackingEndedIsSafeToCallWithoutOrBeforeABuild() {
        let session = MenuTrackingSession()
        let menu = NSMenu()
        session.trackingEnded()
        session.trackingEnded()
        var builds = 0
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }
        XCTAssertEqual(builds, 1, "a stray close must not swallow the next open's build")

        // Close arriving twice (e.g. alongside an item action firing) stays idempotent.
        session.trackingEnded()
        session.trackingEnded()
        session.updateIfNeeded(menu) { builds += 1; return build(state()) }
        XCTAssertEqual(builds, 2)
    }

    /// Grounds the claim the fix rests on: one build already produces the ⌥ pair, so AppKit
    /// has everything it needs to swap them natively and no rebuild is required for ⌥ at all.
    func testASingleBuildAlreadyContainsTheAlternatePair() throws {
        var dualStack = state()
        dualStack.exit6 = ExitInfo(ip: "2a09:bac5:27cd:2a0::43:80", countryCode: "NL",
                                   provider: "ipwho.is", fetchedAt: Date())
        let session = MenuTrackingSession()
        let menu = NSMenu()
        session.updateIfNeeded(menu) { build(dualStack) }
        let ipIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "185.107.56.123" })
        let alternate = menu.items[ipIndex + 1]
        XCTAssertTrue(alternate.isAlternate)
        XCTAssertEqual(alternate.title, L10n.string(.menuCopyExitBoth))
    }
}
