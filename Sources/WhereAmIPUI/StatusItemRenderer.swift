import AppKit
import WhereAmIPCore

// NOTE: Task 14 adds `resources:` to Package.swift, which makes SwiftPM synthesize
// Bundle.module. However, that accessor tries Bundle.main.bundleURL first (app root),
// then a hardcoded .build path, then fatalErrors. But make-app-bundle.sh puts the
// bundle into Contents/MacOS/, not the app root, and the .build path doesn't exist on
// other machines or after `rm -rf .build`. So we do NOT reference Bundle.module here.
// Instead, we use a multi-candidate resolver that mirrors Task-12's lookup order
// (Bundle.main.resourceURL, Bundle(for:).resourceURL, Bundle.main.bundleURL,
// Bundle(for:).bundleURL, two levels up from Bundle(for:), and Bundle.main.executableURL's
// parent — the Contents/MacOS/ directory where make-app-bundle.sh places the bundle).
// If all candidates fail, return a token bundle that will never resolve asset lookups,
// allowing fallback to emoji instead of crashing.
private let flagAssetBundle: Bundle = {
    let bundleName = "whereamip_WhereAmIPUI.bundle"
    let token = Bundle(for: BundleToken.self)
    let candidates = [
        Bundle.main.resourceURL,
        token.resourceURL,
        Bundle.main.bundleURL as URL?,
        token.bundleURL as URL?,
        token.bundleURL.deletingLastPathComponent() as URL?,  // For tests: .../debug/ directory
        token.resourceURL?.deletingLastPathComponent().deletingLastPathComponent(),
        Bundle.main.executableURL?.deletingLastPathComponent(),
    ]
    .compactMap { $0 }
    .map { $0.appendingPathComponent(bundleName) }
    for candidate in candidates {
        if let bundle = Bundle(url: candidate) { return bundle }
    }
    // No bundle found — return token to safely fall back to emoji, never crash.
    return token
}()

private final class BundleToken {}

public enum StatusItemRenderer {
    /// `warning` appends a "⚠️" badge to the title, working uniformly across all three menu
    /// bar styles: for emoji/code (text titles) it's appended after a space; for the SF
    /// Symbol/flag-image styles (nil title, image set) it becomes the whole title, which
    /// NSStatusItem renders alongside the image. The badge covers any confirmed leak kind
    /// (IPv6 or DNS) — the dropdown rows name which one specifically.
    public static func render(_ glyph: Glyph, warning: Bool = false) -> (title: String?, image: NSImage?) {
        let (title, image) = renderGlyph(glyph)
        guard warning else { return (title, image) }
        return (title.map { "\($0) ⚠️" } ?? "⚠️", image)
    }

    private static func renderGlyph(_ glyph: Glyph) -> (title: String?, image: NSImage?) {
        switch glyph {
        case .text(let s): return (s, nil)
        case .symbol(let name):
            let img = NSImage(systemSymbolName: name, accessibilityDescription: name)
            img?.isTemplate = true
            return (nil, img)
        case .flagImage(let iso):
            if let url = flagAssetBundle.url(forResource: "flags/\(iso)", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 21, height: 16)
                return (nil, img)
            }
            // asset missing → fall back to emoji text
            return (Flags.emoji(countryCode: iso) ?? "?", nil)
        }
    }
}
