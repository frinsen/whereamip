import Foundation

/// Detects when the copy of WhereAmIP installed on disk (via Homebrew) is
/// newer than the running process — the "brew upgrade replaced the files but
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

    /// Reads the version + app path of the copy currently installed on disk,
    /// via the stable opt symlink derived from the running bundle's Cellar path.
    ///
    /// Deliberately reads through `opt/whereamip` rather than the running
    /// process's own Cellar directory: after `brew upgrade`, Homebrew may have
    /// already deleted the *old* Cellar keg (the one this process is still
    /// executing from) while installing the new one and repointing `opt` at
    /// it. `opt` always points at whatever is currently installed, so it's the
    /// only path guaranteed to still exist and be current.
    public static func onDisk(bundlePath: String) -> (version: String, appPath: String)? {
        guard let appPath = optAppPath(fromBundlePath: bundlePath) else { return nil }
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        return (version: version, appPath: appPath)
    }
}
