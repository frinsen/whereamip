import AppKit
import WhereAmIPCore

// Flags live in the shared UI resource bundle alongside the strings and welcome
// markdown — see ResourceBundle.swift for why `Bundle.module` is never used and
// what happens when no candidate resolves (a bundle that finds nothing, so this
// falls back to emoji rather than crashing).
private let flagAssetBundle = uiResourceBundle

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
