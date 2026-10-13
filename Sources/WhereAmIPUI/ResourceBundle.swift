import Foundation

// `Bundle.module` is BANNED in this package. SwiftPM's synthesized accessor tries
// Bundle.main.bundleURL first (the app root), then a *hardcoded .build path*, then
// fatalErrors — and make-app-bundle.sh puts the resource bundle into
// Contents/Resources/, while that .build path exists on exactly one machine until
// the next `rm -rf .build`. A distributed .app would therefore crash on the first
// resource lookup. Instead we resolve the bundle ourselves from an ordered list of
// candidate directories, and fall back to a bundle that simply resolves nothing
// (empty lookups) rather than crashing.
//
// This is the one implementation of that pattern for the UI target; every UI
// resource (flag PNGs, en.lproj strings, welcome markdown) lives in the same
// SwiftPM bundle, so they all share it. WhereAmIPCore keeps its own copy for
// relay-ranges.csv — a target can't reach into another target's private helper,
// and Core must not depend on the UI layer.
public enum ResourceBundleLocator {
    /// Every place a SwiftPM resource bundle can legitimately turn up, in the order
    /// we trust them:
    ///   1. `Bundle.main.resourceURL` — Contents/Resources/ of a real .app (where
    ///      make-app-bundle.sh copies it), and the first candidate to hit in
    ///      production.
    ///   2/3. the token bundle's own resource/bundle URL — an already-nested layout.
    ///   4/5. one and two levels up from the token bundle — `.build/debug/` under
    ///      `swift test`, where the .bundle sits next to the test bundle.
    ///   6. the executable's directory — a bare `swift run`/`swift build` layout.
    static func candidates(named name: String, main: Bundle, token: Bundle) -> [URL] {
        [
            main.resourceURL,
            token.resourceURL,
            main.bundleURL as URL?,
            token.bundleURL as URL?,
            token.bundleURL.deletingLastPathComponent() as URL?,
            token.resourceURL?.deletingLastPathComponent().deletingLastPathComponent(),
            main.executableURL?.deletingLastPathComponent(),
        ]
        .compactMap { $0 }
        .map { $0.appendingPathComponent(name) }
    }

    /// First candidate that is an actual loadable bundle, or nil — callers decide
    /// what "nothing found" means for their resource (emoji instead of a flag
    /// image, the key instead of a translation). Never fatalErrors.
    public static func resolve(named name: String, main: Bundle = .main, token: Bundle) -> Bundle? {
        for candidate in candidates(named: name, main: main, token: token) {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }

    /// The directory name SwiftPM gives a target's resource bundle: `<package>_<target>.bundle`
    /// on Apple platforms, a plain `<package>_<target>.resources` directory on Linux.
    public static func bundleName(target: String) -> String {
        #if os(Linux)
        return "whereamip_\(target).resources"
        #else
        return "whereamip_\(target).bundle"
        #endif
    }
}

private final class BundleToken {}

/// The WhereAmIPUI resource bundle — flags, `en.lproj/Localizable.strings`, and the
/// welcome markdown all ship inside this one bundle. Resolved once; on failure this
/// is the token bundle itself, which resolves no resources at all but keeps every
/// lookup returning a harmless nil instead of crashing.
let uiResourceBundle: Bundle = {
    let token = Bundle(for: BundleToken.self)
    return ResourceBundleLocator.resolve(named: ResourceBundleLocator.bundleName(target: "WhereAmIPUI"), token: token) ?? token
}()

/// The bundled flag images (Flagpedia, public domain), for frontends that draw their own
/// status icon rather than going through `StatusItemRenderer` — the Linux panel indicator.
public enum FlagAssets {
    /// `flags/<iso>.png` for a lowercase ISO 3166-1 code, or nil when there is none.
    public static func url(iso: String) -> URL? {
        uiResourceBundle.url(forResource: "flags/\(iso)", withExtension: "png")
    }
}
