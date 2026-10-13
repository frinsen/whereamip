import Foundation
import WhereAmIPUI

/// The bundled Markdown (help, welcome) as Pango markup for a GTK label — the Linux
/// counterpart of `WelcomeContent.rendered`, over the same block structure
/// (`WelcomeContent.blocks`) so both platforms agree on paragraphs, bullets and headings.
///
/// Inline subset, exactly what the copy uses: `**bold**`, `*italic*`, `` `code` `` and
/// `[text](https://…)` links. Everything else is text, escaped — Pango markup is XML, and
/// one stray `<` or `&` in the copy would make GTK reject the whole label.
public enum PangoMarkup {
    public static func render(markdown: String) -> String {
        WelcomeContent.blocks(markdown).map { block in
            (block.isBullet ? WelcomeContent.bulletPrefix : "") + inline(block.text)
        }.joined(separator: "\n\n")
    }

    /// PURE, tested. One block's inline markup → Pango markup.
    public static func inline(_ text: String) -> String {
        var out = ""
        var bold = false, italic = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "`", let close = chars[(i + 1)...].firstIndex(of: "`") {
                out += "<tt>" + escape(String(chars[(i + 1)..<close])) + "</tt>"
                i = close + 1
            } else if c == "[", let link = parseLink(chars, from: i) {
                out += "<a href=\"\(escape(link.url))\">\(escape(link.text))</a>"
                i = link.end
            } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                out += bold ? "</b>" : "<b>"
                bold.toggle()
                i += 2
            } else if c == "*" {
                out += italic ? "</i>" : "<i>"
                italic.toggle()
                i += 1
            } else {
                out += escape(String(c))
                i += 1
            }
        }
        // Unbalanced emphasis in the source must not produce invalid markup.
        if italic { out += "</i>" }
        if bold { out += "</b>" }
        return out
    }

    /// `[text](url)` starting at `start`, for http(s) URLs only; nil leaves the bracket as text.
    static func parseLink(_ chars: [Character], from start: Int) -> (text: String, url: String, end: Int)? {
        guard let closeBracket = chars[(start + 1)...].firstIndex(of: "]"),
              closeBracket + 1 < chars.count, chars[closeBracket + 1] == "(",
              let closeParen = chars[(closeBracket + 2)...].firstIndex(of: ")") else { return nil }
        let url = String(chars[(closeBracket + 2)..<closeParen])
        guard url.hasPrefix("https://") || url.hasPrefix("http://") else { return nil }
        return (String(chars[(start + 1)..<closeBracket]), url, closeParen + 1)
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}
