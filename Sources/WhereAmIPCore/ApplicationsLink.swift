import Foundation

/// Errors thrown by `ApplicationsLink.setLinked`. Both cases are about
/// refusing to do something destructive: never delete a real directory,
/// never link when we can't figure out what to link to.
public enum ApplicationsLinkError: Error, Equatable, CustomStringConvertible {
    /// `linkPath` exists but isn't a symlink WhereAmIP created — could be a
    /// real app someone dragged there, or a stray file. We only ever
    /// create/remove symlinks, so this always throws rather than touching it.
    case pathIsNotSymlink(String)
    /// Couldn't derive a target `.app` path to link to (see `targetPath`).
    case cannotDetermineTarget

    public var description: String {
        switch self {
        case .pathIsNotSymlink(let path):
            return "\(path) exists and isn't a symlink WhereAmIP manages — refusing to touch it. " +
                   "Remove it yourself first if you want WhereAmIP to manage /Applications/WhereAmIP.app."
        case .cannotDetermineTarget:
            return "Could not determine which WhereAmIP.app to link to."
        }
    }
}

/// Manages the optional `/Applications/WhereAmIP.app` symlink some users want
/// so the app shows up in Spotlight/Launchpad/Finder the way a "normal"
/// .app does, without Homebrew formulae writing outside their own prefix
/// (`opt`/`Cellar`) themselves — the symlink is created lazily, only when a
/// user opts in via the menu or the first-run window.
///
/// Every function takes injectable paths so this is fully testable against a
/// temp directory — nothing here talks to the real `/Applications` unless a
/// caller passes that path explicitly (which is what the app/CLI do by
/// default).
public enum ApplicationsLink {

    /// Where a `setLinked(true, bundlePath:)` call would point the symlink at,
    /// given the path of the *running* app bundle.
    ///
    /// - Cellar-installed bundle (`.../Cellar/whereamip/<version>/libexec/WhereAmIP.app`):
    ///   returns the version-stable `opt` path, via `InstalledVersion.optAppPath` —
    ///   so the /Applications symlink survives `brew upgrade` without being
    ///   re-pointed at a keg that may get deleted.
    /// - Anything else (dev builds in `dist/`, prebuilt-zip downloads, already
    ///   symlinked from /Applications, …): returns `bundlePath` itself. There's
    ///   no stable "installed" location to prefer outside a Cellar install, so
    ///   the toggle just links whatever bundle is currently running — that's
    ///   fine, it still works, it just won't out-live that particular copy.
    public static func targetPath(fromBundlePath bundlePath: String) -> String? {
        guard !bundlePath.isEmpty else { return nil }
        return InstalledVersion.optAppPath(fromBundlePath: bundlePath) ?? bundlePath
    }

    /// Derives the installed `WhereAmIP.app` path from the *CLI's own*
    /// executable path — used by `whereamip config set applications …`, which
    /// (unlike the .app) has no bundle path of its own to reason from.
    ///
    /// The CLI binary lives at `<prefix>/Cellar/whereamip/<version>/libexec/cli/whereamip`,
    /// reached either directly or via the `<prefix>/bin/whereamip` symlink (itself
    /// pointing at `<prefix>/Cellar/whereamip/<version>/bin/whereamip`, another
    /// symlink). `Bundle.main`/`CommandLine.arguments[0]` report whichever of
    /// those paths the process was invoked as, unresolved — so this fully
    /// resolves the symlink chain first, then reuses the same Cellar-prefix
    /// parsing as `InstalledVersion.optAppPath`, but always targeting
    /// `libexec/WhereAmIP.app` (the CLI's own "rest" — `bin/whereamip` or
    /// `libexec/cli/whereamip` — is irrelevant; we want the app bundle, not
    /// the CLI's own opt-path mirror).
    public static func appPath(fromExecutablePath executablePath: String) -> String? {
        guard !executablePath.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        let components = resolved.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let cellarIndex = components.firstIndex(of: "Cellar"),
              components.count > cellarIndex + 2,
              components[cellarIndex + 1] == "whereamip"
        else { return nil }
        let prefixPath = "/" + components[..<cellarIndex].joined(separator: "/")
        return "\(prefixPath)/opt/whereamip/libexec/WhereAmIP.app"
    }

    /// True when `linkPath` is either a symlink (pointing anywhere, even a
    /// dangling target — still "linked" from the user's point of view) or a
    /// real directory (someone's actual app, or a leftover we must never
    /// delete). False only when nothing at all exists there.
    public static func isLinked(linkPath: String = "/Applications/WhereAmIP.app") -> Bool {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: linkPath)) != nil { return true }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: linkPath, isDirectory: &isDir) && isDir.boolValue
    }

    /// Turns the `/Applications/WhereAmIP.app` symlink on or off.
    ///
    /// - `on`: `ln -sfn` semantics — remove an existing symlink (if any) and
    ///   recreate it pointing at `targetPath(fromBundlePath:)`, so re-running
    ///   with the toggle already on is idempotent and self-healing.
    /// - `off`: remove the symlink if (and only if) `linkPath` is a symlink.
    ///
    /// In both directions, a `linkPath` that exists but is **not** a symlink
    /// (a real directory, a plain file) is never touched — `setLinked` throws
    /// `ApplicationsLinkError.pathIsNotSymlink` instead of deleting it.
    public static func setLinked(_ on: Bool, bundlePath: String,
                                  linkPath: String = "/Applications/WhereAmIP.app") throws {
        let fm = FileManager.default
        let existingSymlinkTarget = try? fm.destinationOfSymbolicLink(atPath: linkPath)

        if on {
            guard let target = targetPath(fromBundlePath: bundlePath) else {
                throw ApplicationsLinkError.cannotDetermineTarget
            }
            if existingSymlinkTarget != nil {
                try fm.removeItem(atPath: linkPath)
            } else if fm.fileExists(atPath: linkPath) {
                throw ApplicationsLinkError.pathIsNotSymlink(linkPath)
            }
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
        } else {
            guard existingSymlinkTarget != nil else {
                if fm.fileExists(atPath: linkPath) {
                    throw ApplicationsLinkError.pathIsNotSymlink(linkPath)
                }
                return // nothing there — unlinking an absent link is a no-op, not an error
            }
            try fm.removeItem(atPath: linkPath)
        }
    }
}
