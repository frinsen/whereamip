import Foundation

/// Preferred-language lookup for the bundled Markdown (welcome copy, help copy).
///
/// The `.strings` tables get their localization for free — `Bundle.localizedString` matches
/// `en.lproj`/`de.lproj` against the user's language list itself, so adding a locale there is
/// a file and nothing more. The Markdown does NOT: those folders are declared `.copy` in
/// Package.swift, which preserves them verbatim rather than treating them as localized
/// resources, and `.process`-ing them into `.lproj` instead would break the flag PNGs and the
/// per-milestone file naming that the welcome window depends on. So this layer does by hand,
/// for two folders, what the strings loader does automatically.
///
/// Layout: the English copy stays where it always was (`welcome/intro.md`), and a translation
/// lives in a language subfolder beside it (`welcome/de/intro.md`). That keeps the base case
/// untouched — no moved files, no changed lookups for English — and makes a translation a
/// pure addition. It also stays inside the ResourceBundleLocator pattern: everything is still
/// resolved through `Bundle.url(forResource:withExtension:)` on the located bundle, never
/// through `Bundle.module` (banned here) or a constructed path.
enum LocalizedMarkdown {
    /// The language the un-suffixed files are written in. Reaching it in the preference list
    /// stops the search: if English outranks German for this user, English is what they want,
    /// even when a German file exists.
    static let baseLanguage = "en"

    /// Markdown for `folder/name`, in the best available language, or nil when even the base
    /// file is missing or empty. Callers decide what "missing" means for their surface — the
    /// welcome window falls back to the intro pitch, the help window to a single sentence.
    ///
    /// `preferredLanguages` is injected (defaulting to the real user preference) so the
    /// language-selection rules are testable without touching system settings.
    static func load(folder: String, name: String, bundle: Bundle,
                     preferredLanguages: [String] = L10n.effectiveLanguages()) -> String? {
        for language in preferredLanguages {
            // "de-DE", "de_DE", "de" all mean the same folder here. Region variants are
            // deliberately NOT separate files: a de-AT reader is far better served by German
            // than by English, and one German file is what a solo maintainer can keep true.
            let code = language.prefix { $0 != "-" && $0 != "_" }.lowercased()
            if code == baseLanguage { break }
            if let text = read("\(folder)/\(code)/\(name)", from: bundle) { return text }
            // A missing translation is not the end of the search: the next preferred language
            // still gets its turn, and the base file is the last resort below.
        }
        return read("\(folder)/\(name)", from: bundle)
    }

    /// An empty (or whitespace-only) file counts as missing — a half-finished translation
    /// must fall back to real copy rather than opening a blank window.
    private static func read(_ resource: String, from bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
