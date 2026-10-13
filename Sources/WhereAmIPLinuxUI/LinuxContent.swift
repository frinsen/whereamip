import Foundation
import WhereAmIPCore
import WhereAmIPUI

private final class BundleToken {}

/// Copy that exists only on Linux: the help window and the first-run window, rewritten for
/// a panel indicator (no ⌘ shortcuts, no notch, no macOS settings panes). Same loader and
/// the same per-file language fallback as the macOS copy (`LocalizedMarkdown`), from this
/// target's own resource bundle.
public enum LinuxContent {
    static let bundle: Bundle = {
        let token = Bundle(for: BundleToken.self)
        return ResourceBundleLocator.resolve(named: ResourceBundleLocator.bundleName(target: "WhereAmIPLinuxUI"),
                                             token: token) ?? token
    }()

    static let helpFallback =
        "Help is unavailable in this build. The full documentation lives at github.com/frinsen/whereamip."
    static let welcomeFallback =
        "WhereAmIP shows the country flag of your real internet exit in the panel."

    public static func helpMarkdown(preferredLanguages: [String] = L10n.effectiveLanguages()) -> String {
        LocalizedMarkdown.load(folder: "help", name: "help", bundle: bundle,
                               preferredLanguages: preferredLanguages) ?? helpFallback
    }

    public static func welcomeMarkdown(preferredLanguages: [String] = L10n.effectiveLanguages()) -> String {
        LocalizedMarkdown.load(folder: "welcome", name: "intro", bundle: bundle,
                               preferredLanguages: preferredLanguages) ?? welcomeFallback
    }

    /// The first-run window opens once, on a first run. The macOS milestone re-show is not
    /// carried over: its highlights describe macOS releases, and the Linux build has no
    /// release history of its own yet. Done stores the milestone exactly as on macOS, so
    /// the two stay compatible if that changes.
    public static func shouldShowWelcome(storedMilestone: String) -> Bool {
        storedMilestone.isEmpty
    }

    /// The bundled flag image for a lowercase ISO code, from the shared UI resources.
    public static func flagImageURL(iso: String) -> URL? {
        guard iso.count == 2, iso.allSatisfy({ ("a"..."z").contains($0) }) else { return nil }
        return FlagAssets.url(iso: iso)
    }
}
