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
                                          systemPreference: [String] = AppLanguage.systemPreferredLanguages) -> [String] {
        guard let code = overrideCode(stored) else { return systemPreference }
        return [code]
    }

    /// The user's language list as their system states it — what "System Language" follows.
    ///
    /// On Linux this cannot come from Foundation: swift-corelibs-foundation answers
    /// `Locale.preferredLanguages` (and `Locale.current`) from its own defaults, never from
    /// the desktop session, so a German desktop would get an English app. The session's
    /// language lives in the POSIX environment instead (see `posixPreferredLanguages`).
    public static var systemPreferredLanguages: [String] {
        #if os(Linux)
        return posixPreferredLanguages(environment: ProcessInfo.processInfo.environment)
        #else
        return Locale.preferredLanguages
        #endif
    }

    /// The first language in `languages` this build ships ("de-AT" → "de"), in preference
    /// order — or nil when none is. Region variants share their language's translation, the
    /// same rule `LocalizedMarkdown` applies to the bundled Markdown.
    public static func firstSupported(in languages: [String]) -> String? {
        for language in languages {
            let code = language.prefix { $0 != "-" && $0 != "_" }.lowercased()
            if supported.contains(code) { return code }
        }
        return nil
    }

    /// PURE, tested. The language list gettext would use: `LANGUAGE` (a colon-separated
    /// priority list) first — ignored, as gettext ignores it, when the locale itself is C or
    /// POSIX — then the first one set of `LC_ALL`, `LC_MESSAGES`, `LANG`. `de_DE.UTF-8@euro`
    /// becomes the BCP 47 tag `de-DE`; C/POSIX mean "no preference" and yield nothing.
    public static func posixPreferredLanguages(environment: [String: String]) -> [String] {
        let locale = ["LC_ALL", "LC_MESSAGES", "LANG"].lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
        guard let primary = locale.flatMap(languageTag) else { return [] }
        let list = (environment["LANGUAGE"] ?? "").split(separator: ":").compactMap { languageTag(String($0)) }
        var out: [String] = []
        for tag in list + [primary] where !out.contains(tag) { out.append(tag) }
        return out
    }

    /// The locale dates are formatted in: `Locale.current` on macOS; on Linux the session's
    /// `LC_ALL` / `LC_TIME` / `LANG`, for the same reason as `systemPreferredLanguages`.
    public static var systemLocale: Locale {
        #if os(Linux)
        let environment = ProcessInfo.processInfo.environment
        let posix = ["LC_ALL", "LC_TIME", "LANG"].lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
        guard let tag = posix.flatMap(languageTag) else { return Locale.current }
        return Locale(identifier: tag.replacingOccurrences(of: "-", with: "_"))
        #else
        return Locale.current
        #endif
    }

    /// `de_DE.UTF-8@euro` → `de-DE`; nil for C, POSIX and anything without a language.
    static func languageTag(_ posix: String) -> String? {
        let base = posix.prefix { $0 != "." && $0 != "@" }
        guard !base.isEmpty, base != "C", base != "POSIX" else { return nil }
        let parts = base.split(separator: "_", maxSplits: 1)
        guard let language = parts.first, language.count >= 2, language.allSatisfy(\.isLetter) else { return nil }
        return parts.count == 2 ? "\(language)-\(parts[1])" : String(language)
    }
}
