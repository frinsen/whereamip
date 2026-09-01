import Foundation

/// Decides which copy of WhereAmIP survives when more than one is running.
///
/// The field bug (maintainer's machine, after a restart): TWO menu bar icons, v0.6 from
/// the Homebrew Cellar and v0.5.5 from a years-old `dist/` dev build. Neither was launched
/// by hand — macOS Background Task Management held two login-item registrations. One
/// belonged to the current brew install; the other was a stale record from a dev build
/// that predated the bundle-id rename (see `legacyBundleIdentifier`), still naming a path
/// where a different version now sat. BTM launches whatever occupies a registered path, so
/// two records mean two launches.
///
/// It is not a maintainer-only accident. `SMAppService`'s registration is keyed by path as
/// well as identity, and Homebrew's Cellar paths carry the version number — so every
/// `brew upgrade` orphans the old record and the re-toggle the README asks for writes a
/// SECOND one. Registrations rot; that is the environment this app lives in. So the app
/// resolves the duplicate itself, at launch, instead of asking the user to keep BTM tidy.
///
/// Pure and clock-free (dates are passed in, never read here) because the code that acts on
/// it — enumerating `NSWorkspace.shared.runningApplications`, terminating a sibling — lives
/// in AppDelegate, which has no test target. Same split as `UpdateCheckSchedule`: the
/// decision is testable even though its caller is not.
public enum InstanceArbiter {

    /// What this instance should do about the other copies it found.
    public enum Verdict: Equatable {
        /// Nobody else is running (or nobody else that concerns us): carry on and build UI.
        case proceed
        /// Someone else has the better claim: terminate quietly, before any UI exists.
        case yield
        /// We have the better claim: ask the others to quit, then carry on.
        case takeOver
    }

    /// One running copy, reduced to the two facts the decision turns on. Both are optional
    /// because both come from a bundle we do not control: `CFBundleShortVersionString` may
    /// be missing or unreadable, and `NSRunningApplication.launchDate` is documented to be
    /// nil for processes AppKit cannot date.
    public struct Instance: Equatable {
        public let version: String?
        public let startedAt: Date?

        public init(version: String?, startedAt: Date?) {
            self.version = version
            self.startedAt = startedAt
        }
    }

    /// The pre-2026-08-13 bundle identifier. Registrations made under it are still in the
    /// field — the whole reason this file exists — and a copy launched from one identifies
    /// itself with THIS string, never with `Bundle.main.bundleIdentifier`. Matching on our
    /// own identifier alone would walk straight past the instance we are trying to resolve.
    ///
    /// Keep it forever, even when no legacy build plausibly remains: BTM records outlive
    /// apps by design (Apple persists them "to preserve user intent"), there is no API to
    /// enumerate or delete a single one, and the only cleanup tool — `sudo sfltool resetbtm`
    /// — wipes every third-party login item on the machine, which is not something an app
    /// should do to someone.
    public static let legacyBundleIdentifier = "io.github.martinfrindt.whereamip"

    /// Whether a running application is another copy of us: our own identifier, or the
    /// legacy one above. Compared case-insensitively, as Launch Services treats bundle
    /// identifiers, and never by prefix — `…whereamip.helper` is a neighbour, not us.
    ///
    /// A pure function with its own tests rather than a closure inside the AppKit filter,
    /// so the one rule that decides "is this me?" is not the untested part.
    public static func isSibling(bundleIdentifier: String?, ownIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier, !id.isEmpty else { return false }
        if let own = ownIdentifier, !own.isEmpty, id.caseInsensitiveCompare(own) == .orderedSame {
            return true
        }
        return id.caseInsensitiveCompare(legacyBundleIdentifier) == .orderedSame
    }

    /// The verdict across every other copy found. `.proceed` when there are none.
    ///
    /// A single `.yield` anywhere wins: if some other copy is newer than us, we leave — and
    /// we leave without terminating the older copies on the way out, because the newer one
    /// will make that call for itself and a departing process should not be reshaping the
    /// field behind it.
    public static func verdict(_ mine: Instance, versus others: [Instance]) -> Verdict {
        guard !others.isEmpty else { return .proceed }
        return others.contains { decide(mine, versus: $0) == .yield } ? .yield : .takeOver
    }

    /// The pairwise rule. Never `.proceed`: with another copy on screen, someone has to go.
    ///
    /// 1. Newest version wins. That is what makes the guard safe next to the restart-to-
    ///    finish-update flow — if the old copy and the freshly relaunched one ever overlap,
    ///    the NEW one takes over, which is the outcome the update was aiming for anyway.
    /// 2. Unreadable or unparseable versions count as older, so a broken bundle can never
    ///    displace a healthy one. Symmetrically, if OUR version is the unreadable one we
    ///    yield to a readable other, for the same reason from the other side.
    /// 3. Equal versions — the boot race, two BTM records launching the same build — break
    ///    on start time: the instance that started first keeps the menu bar, and the
    ///    latecomer leaves. An unknown start time counts as "started later", so the copy we
    ///    know least about is the one that goes.
    /// 4. An exact tie yields. Both halves of a tie reaching `.takeOver` would have them
    ///    terminate each other; both reaching `.yield` at worst leaves the menu bar empty
    ///    until the next launch. Neither is good, and only one of them is recoverable by
    ///    clicking the app again. (Real launch dates never tie to the microsecond; this is
    ///    the both-dates-unknown case, and a guarantee that the rule is antisymmetric.)
    public static func decide(_ mine: Instance, versus other: Instance) -> Verdict {
        switch versionOrder(mine.version, other.version) {
        case .otherIsNewer: return .yield
        case .otherIsOlder: return .takeOver
        case .same:
            // Unknown start time sorts last, so a dated instance always beats an undated
            // one and two undated ones land on the exact-tie rule.
            let ours = mine.startedAt ?? .distantFuture
            let theirs = other.startedAt ?? .distantFuture
            return theirs <= ours ? .yield : .takeOver
        }
    }

    private enum VersionOrder { case otherIsNewer, otherIsOlder, same }

    private static func versionOrder(_ mine: String?, _ other: String?) -> VersionOrder {
        let mineParses = mine.map(SemVer.parses) ?? false
        let otherParses = other.map(SemVer.parses) ?? false
        switch (mineParses, otherParses) {
        case (true, false): return .otherIsOlder
        case (false, true): return .otherIsNewer
        case (false, false): return .same
        case (true, true):
            guard let mine, let other else { return .same }   // unreachable; no force-unwrap
            if SemVer.isNewer(other, than: mine) { return .otherIsNewer }
            if SemVer.isNewer(mine, than: other) { return .otherIsOlder }
            return .same
        }
    }
}
