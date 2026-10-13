import Foundation
import WhereAmIPCore

/// What the panel should show, decided from the same `Glyph` the macOS status item renders
/// — and named, because an AppIndicator icon is a FILE the panel loads by name.
///
/// macOS draws text and template symbols straight into the menu bar. A panel indicator can
/// only show an image (labels are not supported by every panel — elementary OS's is one
/// that ignores them), so every style becomes a small square PNG: the flag image, the
/// emoji flag drawn by the colour-emoji font, or the ISO code on a badge. Square because
/// panels fit icons into a square slot (elementary's into 16×16), and a wide image would
/// shrink to a sliver there.
public struct PanelIcon: Equatable, Hashable, Sendable {
    public enum Content: Equatable, Hashable, Sendable {
        /// A bundled flag image, by lowercase ISO code.
        case flag(iso: String)
        /// Text drawn on a badge — an emoji flag or an ISO code.
        case text(String)
        /// Nothing actually loads right now (the macOS `network.slash`).
        case offline
        /// Online, but the exit could not be placed (the macOS `questionmark`).
        case unknown
    }

    public var content: Content
    /// A confirmed leak (IPv6 or DNS): the macOS "⚠️" badge, drawn into the icon's corner.
    public var warning: Bool
    /// The manual-refresh cue: macOS dims the status button, this dims the icon.
    public var dimmed: Bool

    public init(content: Content, warning: Bool = false, dimmed: Bool = false) {
        self.content = content; self.warning = warning; self.dimmed = dimmed
    }

    /// The same decision `StatusItemRenderer` makes on macOS: the glyph for the chosen style,
    /// badged on exactly the condition the status item badges on.
    public static func forState(_ state: ExitState, style: MenuBarStyle, dimmed: Bool = false) -> PanelIcon {
        let content: Content
        switch state.glyph(style: style) {
        case .text(let text): content = .text(text)
        case .flagImage(let iso): content = .flag(iso: iso)
        case .symbol(let name): content = name == "network.slash" ? .offline : .unknown
        }
        return PanelIcon(content: content, warning: state.ipv6Leak || state.dns.leak == .confirmed, dimmed: dimmed)
    }

    /// A file name that is a pure function of what the icon shows. Panels cache icons by
    /// name, so a name must never be reused for different pixels — and deriving it from the
    /// content guarantees that.
    public var fileStem: String {
        let base: String
        switch content {
        case .flag(let iso): base = "flag-\(Self.safe(iso))"
        case .text(let text): base = "text-" + text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        case .offline: base = "offline"
        case .unknown: base = "unknown"
        }
        return "whereamip-\(base)\(warning ? "-warn" : "")\(dimmed ? "-dim" : "")"
    }

    /// The tooltip/accessibility text panels show on hover.
    public var accessibleDescription: String {
        switch content {
        case .flag(let iso): return iso.uppercased()
        case .text(let text): return text
        case .offline: return "offline"
        case .unknown: return "unknown exit"
        }
    }

    private static func safe(_ s: String) -> String {
        String(s.lowercased().filter { ("a"..."z").contains($0) }.prefix(8))
    }
}
