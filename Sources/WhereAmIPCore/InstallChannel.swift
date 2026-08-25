import Foundation

/// How the running copy of WhereAmIP got onto this Mac, derived purely from its own
/// path — the same trick `InstalledVersion.optAppPath` and `ApplicationsLink` already
/// use, widened from "Homebrew or not" to the three channels that actually ship.
///
/// This exists because the update row used to hand everyone the Homebrew command. It is
/// wrong for a MacPorts install (a second copy through another package manager) and
/// wrong for a release-zip install (there is nothing to upgrade). The MacPorts Portfile
/// worked around it by *patching* the command string — and the test that guarded it —
/// during `post-patch`; deriving the channel here is what lets that block go away.
///
/// Pure and injectable: nothing here touches the filesystem, so every layout below is
/// testable without being installed that way. Callers pass a fully resolved path where
/// they can (`Bundle.main.bundlePath` already is one); an unresolved symlink such as
/// `<prefix>/bin/whereamip` classifies as `.direct`, which is the safe answer — it
/// offers a download page rather than a command that might not fit.
public enum InstallChannel: String, Sendable, CaseIterable {
    /// Installed from the `frinsen/tap` Homebrew formula.
    case homebrew
    /// Installed from the `net/whereamip` MacPorts port.
    case macports
    /// Everything else: the GitHub release zip, a `dist/` build, a hand-placed copy.
    case direct

    public static func detect(path: String) -> InstallChannel {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // Homebrew, both of its stable shapes:
        //   <prefix>/Cellar/whereamip/<version>/…  — the keg the formula installs into
        //   <prefix>/opt/whereamip/…               — the version-stable link, which is
        //                                            what /Applications/WhereAmIP.app
        //                                            points at (ApplicationsLink) and so
        //                                            what a launch through that symlink
        //                                            reports as its bundle path.
        // Both are checked before MacPorts because a Homebrew prefix can sit anywhere,
        // including under /opt.
        if isComponent("Cellar", followedByWhereamipIn: components) { return .homebrew }
        if isComponent("opt", followedByWhereamipIn: components) { return .homebrew }

        // MacPorts, the two layouts the Portfile destroots into:
        //   ${applications_dir}/WhereAmIP.app        — /Applications/MacPorts by default,
        //                                              configurable, but always named
        //                                              MacPorts
        //   ${prefix}/libexec/whereamip/whereamip    — /opt/local by default; the CLI and
        //                                              its resource bundle live together
        //                                              there, with ${prefix}/bin/whereamip
        //                                              a symlink to it
        // `prefix` is deliberately not hardcoded: MacPorts can be installed anywhere.
        if components.contains("MacPorts") { return .macports }
        if isComponent("libexec", followedByWhereamipIn: components) { return .macports }

        return .direct
    }

    /// True when `name` appears as a path component immediately followed by `whereamip`.
    ///
    /// Every occurrence is checked, not just the first: `/opt/homebrew/opt/whereamip/…`
    /// carries two `opt` components and only the second one is the interesting one.
    ///
    /// Case matters: Homebrew's `libexec` holds `WhereAmIP.app` and `cli/`, the port's
    /// holds a `whereamip` directory, and that difference is the whole discriminator.
    private static func isComponent(_ name: String, followedByWhereamipIn components: [String]) -> Bool {
        components.indices.contains {
            components[$0] == name && $0 + 1 < components.count && components[$0 + 1] == "whereamip"
        }
    }
}
