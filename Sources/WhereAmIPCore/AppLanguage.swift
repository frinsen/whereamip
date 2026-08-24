import Foundation

/// The app's UI language: follow the system, or override it in-app.
///
/// macOS already offers a per-app language in System Settings, but it costs a relaunch and
/// is three levels deep in a place most people never look. This app owns its entire text
/// pipeline — `L10n` resolves through our own bundle locator and `LocalizedMarkdown` walks a
/// language list we hand it — so an override can take effect on the next menu open instead,
/// with no relaunch. That is the whole reason this type exists as a resolved LIST rather
/// than a stored string: both consumers ask the same question and get the same answer.
///
/// Deliberately NOT covered: `whereamip` output, the JSON, the ⌘D report and the log. This
/// setting names the language of the UI, not of the diagnostics — see DiagnosticsReport for
/// why those stay English.
public enum AppLanguage {
    /// Stored value meaning "whatever the Mac is set to" — the default, and the only value
    /// that is not a language code.
    public static let system = "system"

    /// Language codes with a complete `.lproj` in the bundle. The folders are the source of
    /// truth; this is the menu- and CLI-facing copy of that list, held to it by
    /// `L10nTests.shippedLocales` on the bundle side and `AppLanguageTests` on this side.
    public static let supported = ["en", "de"]

    /// The stored value as an actual override, or nil for "system" — and for anything this
    /// build cannot display. A value can outlive the build that wrote it (a downgrade, a
    /// hand-edited plist), and an unshowable language must degrade to the system default
    /// rather than to a window full of raw keys.
    public static func overrideCode(_ stored: String) -> String? {
        supported.contains(stored) ? stored : nil
    }

    /// The language list every text lookup should consult.
    ///
    /// An override REPLACES the system list rather than being prepended to it: someone who
    /// picks English on a German Mac wants English, and a half-translated file falling
    /// through to German would be a worse answer than the honest per-file English fallback
    /// that `LocalizedMarkdown` already provides.
    public static func effectiveLanguages(override stored: String,
                                          systemPreference: [String] = Locale.preferredLanguages) -> [String] {
        guard let code = overrideCode(stored) else { return systemPreference }
        return [code]
    }
}
