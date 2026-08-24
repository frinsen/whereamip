import Foundation

/// Numeric segment-wise semver-ish comparison. Tolerates a leading "v" and a
/// "-prerelease" suffix; only the dotted numeric core is compared. A
/// prerelease build of the same core (e.g. "0.3-beta.1" vs "0.3") is treated
/// as NOT newer — it's the same release, not a step forward. Anything that
/// doesn't parse as a dotted numeric core is treated as not newer, never
/// crashes or throws.
public enum SemVer {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let c = coreComponents(candidate), let b = coreComponents(current) else { return false }
        return compare(c, b) > 0
    }

    private static func coreComponents(_ raw: String) -> [Int]? {
        var s = Substring(raw)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = s[s.startIndex..<dash] }
        guard !s.isEmpty else { return nil }
        var nums: [Int] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part) else { return nil }
            nums.append(n)
        }
        return nums.isEmpty ? nil : nums
    }

    private static func compare(_ a: [Int], _ b: [Int]) -> Int {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

/// When an opportunistic update check is allowed to happen.
///
/// The daily timer alone means a release published just after it ran stays invisible for up
/// to 24 hours — a beta tester hit exactly that. A full refresh already happens on launch,
/// on wake, every 5 minutes and on manual Refresh, so it is a free place to ask "has it been
/// a while?" without adding a second timer.
///
/// Throttles ATTEMPTS, not successes, deliberately: keying off the last SUCCESS would turn a
/// GitHub outage into a request on every 5-minute refresh — hammering an API that is already
/// failing, from every installed copy at once. A transient failure therefore delays the next
/// opportunistic attempt by the full interval, which is acceptable precisely because the
/// daily timer is still there as the backstop.
///
/// Pure and clock-injected because the code that acts on it lives in AppDelegate, which has
/// no test target — the decision is testable even though its caller is not.
public enum UpdateCheckSchedule {
    /// Six hours: roughly 2-3 extra requests a day per install, and it turns a worst case of
    /// "a day late" into "a few hours late".
    public static let opportunisticInterval: TimeInterval = 6 * 60 * 60

    public static func shouldAttempt(lastAttempt: Date?, now: Date = Date(), enabled: Bool) -> Bool {
        // The setting is absolute — README promises no request is EVER made when it is off,
        // and an opportunistic path is where such a promise erodes by accident.
        guard enabled else { return false }
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        // A negative interval means the stored attempt is in the future: the clock moved
        // backwards (travel, an NTP correction, a long sleep). Waiting the interval out from
        // a future instant could suppress checks for far longer than intended, so treat
        // nonsense as stale — one extra request is the cheaper mistake.
        return elapsed < 0 || elapsed >= opportunisticInterval
    }
}

/// Passive update check against the latest GitHub release. Never downloads
/// or applies anything — it only reports a version string for the UI to
/// display, leaving the actual upgrade to `UpdateChecker.upgradeCommand`.
public struct UpdateChecker: Sendable {
    /// The command the dropdown's update row puts on the clipboard.
    ///
    /// `brew update &&` is not decoration. WhereAmIP is installed from a third-party TAP,
    /// which Homebrew keeps as a git clone — and `brew upgrade <formula>` does not reliably
    /// pull it. Homebrew's API mode refreshes the core/cask JSON, not tap clones, so on a
    /// stale clone the upgrade cheerfully reports the OLD version as already installed and
    /// does nothing. Field-reported by a beta tester who saw "0.4.2 already installed" hours
    /// after 0.5 was on the tap. Only an explicit `brew update` refreshes the clone, so the
    /// command we hand people has to include it.
    ///
    /// Single source of truth: the row's clipboard payload uses this, and it is what the
    /// tests assert against — the string must never quietly regress to the bare upgrade.
    public static let upgradeCommand = "brew update && brew upgrade whereamip"

    private let session: URLSession
    private let deadline: Double
    static let url = URL(string: "https://api.github.com/repos/frinsen/whereamip/releases/latest")!

    public init(session: URLSession = URLSession(configuration: .default), deadlineSeconds: Double = 5) {
        self.session = session
        self.deadline = deadlineSeconds
    }

    /// Returns the latest release's version (leading "v" stripped), or nil on
    /// any failure — network error, non-200, timeout, or unparseable JSON.
    public func latestVersion() async -> String? {
        do {
            let version = try await withHardDeadline(seconds: deadline) { [session] in
                let (data, resp) = try await session.data(from: Self.url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw BadResponse() }
                let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                guard var tag = o["tag_name"] as? String else { throw BadResponse() }
                if tag.first == "v" || tag.first == "V" { tag.removeFirst() }
                return tag
            }
            Log.update.debug("check: latest=\(version, privacy: .public)")
            return version
        } catch {
            Log.update.debug("check: failed")
            return nil
        }
    }
}
