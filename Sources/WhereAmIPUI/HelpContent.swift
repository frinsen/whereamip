import Foundation

/// The help window's body copy: one bundled Markdown file, `Resources/help/help.md`.
///
/// Same reasoning as `WelcomeContent`'s markdown — this is prose with structure, not
/// a set of labels, so it lives in a file the maintainer can edit and re-read at a
/// glance rather than in a `.strings` table one sentence per line. It sits in its own
/// `help/` directory rather than inside `welcome/` because the two have different
/// lifetimes: welcome copy is per-release and gets a new file each milestone, help
/// copy is one evergreen document that gets edited in place.
///
/// Loaded through `uiResourceBundle` (never `Bundle.module`, which is banned here —
/// see ResourceBundle.swift) and rendered by `WelcomeContent.rendered`, the same
/// minimal Markdown renderer the welcome window uses. Section titles in help.md are
/// therefore written as `**bold paragraphs**`, not `#` headings: the renderer strips
/// hashes without styling what's left, so a `#` line would read as an ordinary
/// paragraph.
public enum HelpContent {
    /// Last resort when the resource bundle can't be found at all — the same
    /// never-crash convention as `WelcomeContent.fallbackPitch`. It must stay a true
    /// sentence: a raw path or a lookup key on screen is a worse bug than terse copy.
    static let fallback =
        "Help is unavailable in this build. The full documentation lives at "
        + "github.com/frinsen/whereamip."

    /// Bundled help copy, or `fallback` when the file is missing or empty.
    public static func markdown() -> String { markdown(in: uiResourceBundle) }

    /// Bundle-injecting variant, so the missing/empty cases are testable against a
    /// bundle that genuinely resolves nothing.
    static func markdown(in bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: "help/help", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
