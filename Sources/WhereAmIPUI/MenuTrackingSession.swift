import AppKit

/// Builds the dropdown's item tree ONCE per menu-tracking session.
///
/// `menuNeedsUpdate` is not a once-per-open callback. AppKit also calls it on every keydown
/// while a menu is tracking — modifier presses included, since that is exactly when it
/// re-evaluates which of an alternate pair to show. The delegate used to rebuild the whole
/// menu there, so every ⌥ press and every ⌥ release removed ~20 item views from an OPEN
/// menu and inserted 20 new ones: a visible jump, and the hover highlight lost under the
/// cursor. Field-reported on v0.5.
///
/// The rebuild was never needed for the alternates themselves — AppKit swaps an
/// `isAlternate` pair natively from the modifier state, using items that are already there
/// (see `MenuTrackingSessionTests.testASingleBuildAlreadyContainsTheAlternatePair`). Our
/// rebuild was pure interference with that mechanism.
///
/// Deliberate consequence: a Monitor refresh that lands WHILE the menu is open is no longer
/// picked up mid-tracking. It used to be, incidentally, via those keydown rebuilds. Not
/// showing it is the better behaviour — rows changing under the cursor mid-click is worse
/// than a reading that is a few seconds old, and the timestamps are explicit about their own
/// age ("Since"/"Checked") rather than pretending to be live. Every open still builds from
/// current state, and manual Refresh closes the menu as it fires, so the next open is fresh.
///
/// Main-thread only, like the AppKit delegate callbacks that drive it; deliberately not
/// thread-safe, because being called from anywhere else would already be the bug.
public final class MenuTrackingSession {
    private var builtForThisSession = false

    public init() {}

    /// Populates `menu` from `build()` on the first call of a tracking session; later calls
    /// in the same session do nothing at all — `build` is not even invoked, so no state is
    /// read and no work is done on the keydown path.
    public func updateIfNeeded(_ menu: NSMenu, build: () -> NSMenu) {
        guard !builtForThisSession else { return }
        builtForThisSession = true
        let fresh = build()
        menu.removeAllItems()
        // Items must be detached from the menu that owns them before they can be adopted:
        // an NSMenuItem belongs to exactly one menu.
        fresh.items.forEach { item in
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    /// The tracking session ended (`menuDidClose`) — the next open builds again.
    ///
    /// Safe in any order relative to an item's action firing, and safe when no build ever
    /// happened: this only ever clears a flag, and nothing in this app reopens the menu from
    /// an action. Selecting an item closes the menu and fires its action; whichever of the
    /// two AppKit sequences first, the flag ends up false and the next open rebuilds.
    public func trackingEnded() {
        builtForThisSession = false
    }
}
