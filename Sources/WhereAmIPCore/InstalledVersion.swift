import Foundation

/// Detects when the copy of WhereAmIP installed on disk (by Homebrew or MacPorts) is
/// newer than the running process — the "the upgrade replaced the files but
/// didn't restart me" case. Pure path derivation plus a single plist read;
/// no network, no process launching (that lives in AppDelegate).
public enum InstalledVersion {

    /// If `fromBundlePath` matches a Homebrew Cellar layout
    /// (`<prefix>/Cellar/whereamip/<version>/<rest>`), returns the
    /// version-stable opt path `<prefix>/opt/whereamip/<rest>`. Returns nil
    /// for anything else (dev builds in dist/, /tmp bundles, /Applications
    /// installs) — the feature is inert there, which is correct: outside a
    /// Cellar install there's no stable "installed" location to compare against.
    public static func optAppPath(fromBundlePath: String) -> String? {
        let components = fromBundlePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let cellarIndex = components.firstIndex(of: "Cellar"),
              components.count > cellarIndex + 2,
              components[cellarIndex + 1] == "whereamip"
        else { return nil }

        // prefix = everything before "Cellar" (e.g. ["opt", "homebrew"] or ["usr", "local"])
        let prefixComponents = components[..<cellarIndex]
        // rest = everything after the version segment (cellarIndex+2)
        let restComponents = components[(cellarIndex + 3)...]
        guard !restComponents.isEmpty else { return nil }

        let prefixPath = "/" + prefixComponents.joined(separator: "/")
        let restPath = restComponents.joined(separator: "/")
        return "\(prefixPath)/opt/whereamip/\(restPath)"
    }

    /// The path that keeps pointing at the CURRENTLY INSTALLED app across an upgrade,
    /// for the channel `bundlePath` belongs to. The one place that knows this differs
    /// per package manager.
    ///
    /// - Homebrew: the version-stable `opt` path (`optAppPath` above). Never the running
    ///   process's own Cellar keg — `brew upgrade` may already have deleted it.
    /// - MacPorts: `bundlePath` itself. There is no versioned keg to indirect through:
    ///   the port destroots the bundle into `${applications_dir}` and activation
    ///   hardlinks it into place, so `/Applications/MacPorts/WhereAmIP.app` is the same
    ///   path before and after `port upgrade`. Deactivating the old version unlinks
    ///   those files and activating the new one links new ones at the same paths, so
    ///   re-reading `Contents/Info.plist` there sees the NEW version while this process
    ///   keeps running from the old inode it already has open — exactly the signal the
    ///   restart row needs. (Reasoned from MacPorts' activation model and stated in the
    ///   port submission notes; not yet confirmed against a live `port upgrade`, which
    ///   is why it is one function with its own tests rather than an assumption spread
    ///   across callers.)
    /// - Direct installs: nil. A zip in /Applications is not managed by anything, so
    ///   nothing can replace it underneath us and there is nothing to compare against.
    public static func installedAppPath(fromBundlePath bundlePath: String) -> String? {
        guard !bundlePath.isEmpty else { return nil }
        switch InstallChannel.detect(path: bundlePath) {
        case .homebrew: return optAppPath(fromBundlePath: bundlePath)
        case .macports: return bundlePath
        case .direct: return nil
        }
    }

    /// Reads the version + app path of the copy currently installed on disk, through
    /// whichever path stays stable across an upgrade for this install channel
    /// (see `installedAppPath`).
    public static func onDisk(bundlePath: String) -> (version: String, appPath: String)? {
        guard let appPath = installedAppPath(fromBundlePath: bundlePath) else { return nil }
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        return (version: version, appPath: appPath)
    }
}
