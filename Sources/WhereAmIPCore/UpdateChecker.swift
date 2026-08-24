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
