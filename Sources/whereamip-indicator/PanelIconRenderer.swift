import CGtk
import Foundation
import WhereAmIPCore
import WhereAmIPLinuxUI

/// Draws `PanelIcon`s as PNG files for the indicator to hand the panel by name.
///
/// The files live in `$XDG_RUNTIME_DIR` — a tmpfs, so drawing them writes nothing to disk,
/// in keeping with the README's promise — and are named by their content (see
/// `PanelIcon.fileStem`), so each distinct icon is drawn once per session and a cached name
/// can never come back with different pixels.
final class PanelIconRenderer {
    /// Large enough to stay crisp on a HiDPI panel; panels scale it down to their slot.
    static let size: Int32 = 64

    let directory: String
    private var drawn: Set<String> = []

    init(directory: String) {
        self.directory = directory
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let runtime = environment["XDG_RUNTIME_DIR"], runtime.hasPrefix("/") {
            return "\(runtime)/whereamip/icons"
        }
        // No runtime dir (rare outside a full desktop session): the per-user cache, which
        // at least is the documented place for regenerable files.
        let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory()
        return "\(environment["XDG_CACHE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "\(home)/.cache")/whereamip/icons"
    }

    /// The icon's name for `app_indicator_set_icon_full`, drawing it first if needed.
    func iconName(for icon: PanelIcon) -> String? {
        let stem = icon.fileStem
        if drawn.contains(stem) { return stem }
        guard draw(icon, to: "\(directory)/\(stem).png") else { return nil }
        drawn.insert(stem)
        return stem
    }

    // MARK: - drawing

    private func draw(_ icon: PanelIcon, to path: String) -> Bool {
        let s = Self.size
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, s, s) else { return false }
        defer { cairo_surface_destroy(surface) }
        guard let cr = cairo_create(surface) else { return false }
        defer { cairo_destroy(cr) }

        cairo_push_group(cr)
        switch icon.content {
        case .flag(let iso):
            if !drawFlag(cr, iso: iso) { drawBadge(cr, text: iso.uppercased()) }
        case .text(let text):
            if Self.isEmojiFlag(text) {
                if !drawEmoji(cr, text), let iso = Self.isoCode(fromEmojiFlag: text), !drawFlag(cr, iso: iso) {
                    drawBadge(cr, text: iso.uppercased())
                }
            } else {
                drawBadge(cr, text: text)
            }
        case .offline:
            if !drawSymbol(cr, "network-offline-symbolic") { drawBadge(cr, text: "✕") }
        case .unknown:
            drawBadge(cr, text: "?")
        }
        if icon.warning { drawWarning(cr) }
        cairo_pop_group_to_source(cr)
        cairo_paint_with_alpha(cr, icon.dimmed ? 0.4 : 1.0)

        cairo_surface_flush(surface)
        return cairo_surface_write_to_png(surface, path) == CAIRO_STATUS_SUCCESS
    }

    /// The bundled flag image, full width, centred vertically, with rounded corners and a
    /// hairline edge so white-edged flags (Japan, Finland) hold up on a light panel.
    private func drawFlag(_ cr: OpaquePointer, iso: String) -> Bool {
        guard let url = LinuxContent.flagImageURL(iso: iso),
              let pixbuf = gdk_pixbuf_new_from_file_at_scale(url.path, Self.size, Self.size, 1, nil) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        let w = Double(gdk_pixbuf_get_width(pixbuf)), h = Double(gdk_pixbuf_get_height(pixbuf))
        let x = (Double(Self.size) - w) / 2, y = (Double(Self.size) - h) / 2
        roundedRect(cr, x, y, w, h, radius: 5)
        cairo_save(cr)
        cairo_clip_preserve(cr)
        gdk_cairo_set_source_pixbuf(cr, pixbuf, x, y)
        cairo_paint(cr)
        cairo_restore(cr)
        cairo_set_source_rgba(cr, 0, 0, 0, 0.35)
        cairo_set_line_width(cr, 2)
        cairo_stroke(cr)
        return true
    }

    /// An emoji flag through the colour-emoji font. False when the font has no glyph for it
    /// (no colour-emoji font installed), so the caller can fall back to the flag image —
    /// two boxed letters are not a flag.
    private func drawEmoji(_ cr: OpaquePointer, _ text: String) -> Bool {
        guard let layout = pango_cairo_create_layout(cr) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        let font = pango_font_description_from_string("Noto Color Emoji 40px")
        pango_layout_set_font_description(layout, font)
        pango_font_description_free(font)
        pango_layout_set_text(layout, text, -1)
        guard pango_layout_get_unknown_glyphs_count(layout) == 0 else { return false }
        var w: Int32 = 0, h: Int32 = 0
        pango_layout_get_pixel_size(layout, &w, &h)
        guard w > 0, h > 0 else { return false }
        let scale = min(Double(Self.size) / Double(w), Double(Self.size) / Double(h))
        cairo_save(cr)
        cairo_translate(cr, (Double(Self.size) - Double(w) * scale) / 2, (Double(Self.size) - Double(h) * scale) / 2)
        cairo_scale(cr, scale, scale)
        pango_cairo_show_layout(cr, layout)
        cairo_restore(cr)
        return true
    }

    /// Short text on a dark rounded badge: legible on light and dark panels alike, which a
    /// bare glyph in one fixed colour is not.
    private func drawBadge(_ cr: OpaquePointer, text: String) {
        let s = Double(Self.size)
        roundedRect(cr, 2, 10, s - 4, s - 20, radius: 9)
        cairo_set_source_rgba(cr, 0.16, 0.16, 0.18, 0.92)
        cairo_fill(cr)
        guard let layout = pango_cairo_create_layout(cr) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        let font = pango_font_description_from_string("Sans Bold 30px")
        pango_layout_set_font_description(layout, font)
        pango_font_description_free(font)
        pango_layout_set_text(layout, text, -1)
        var w: Int32 = 0, h: Int32 = 0
        pango_layout_get_pixel_size(layout, &w, &h)
        let scale = min(1.0, (s - 14) / Double(max(w, 1)))
        cairo_save(cr)
        cairo_translate(cr, (s - Double(w) * scale) / 2, (s - Double(h) * scale) / 2)
        cairo_scale(cr, scale, scale)
        cairo_set_source_rgba(cr, 1, 1, 1, 1)
        pango_cairo_show_layout(cr, layout)
        cairo_restore(cr)
    }

    /// The desktop's own symbolic icon, white on the same badge.
    private func drawSymbol(_ cr: OpaquePointer, _ name: String) -> Bool {
        let s = Double(Self.size)
        guard let pixbuf = wai_load_symbolic_icon(name, 40, 1, 1, 1) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        roundedRect(cr, 2, 2, s - 4, s - 4, radius: 12)
        cairo_set_source_rgba(cr, 0.16, 0.16, 0.18, 0.92)
        cairo_fill(cr)
        let w = Double(gdk_pixbuf_get_width(pixbuf)), h = Double(gdk_pixbuf_get_height(pixbuf))
        gdk_cairo_set_source_pixbuf(cr, pixbuf, (s - w) / 2, (s - h) / 2)
        cairo_paint(cr)
        return true
    }

    /// The macOS "⚠️" badge, as an amber warning triangle in the bottom-right corner.
    private func drawWarning(_ cr: OpaquePointer) {
        let s = Double(Self.size)
        let side = s * 0.55
        let left = s - side - 1, bottom = s - 1, top = s - side * 0.9 - 1
        cairo_move_to(cr, left + side / 2, top)
        cairo_line_to(cr, left + side, bottom)
        cairo_line_to(cr, left, bottom)
        cairo_close_path(cr)
        cairo_set_source_rgba(cr, 0.98, 0.69, 0.10, 1)
        cairo_fill_preserve(cr)
        cairo_set_source_rgba(cr, 0, 0, 0, 0.75)
        cairo_set_line_width(cr, 2)
        cairo_stroke(cr)
        let cx = left + side / 2
        cairo_set_source_rgba(cr, 0.1, 0.1, 0.1, 1)
        cairo_rectangle(cr, cx - 2.5, top + side * 0.28, 5, side * 0.32)
        cairo_fill(cr)
        cairo_rectangle(cr, cx - 2.5, bottom - side * 0.2, 5, 5)
        cairo_fill(cr)
    }

    private func roundedRect(_ cr: OpaquePointer, _ x: Double, _ y: Double, _ w: Double, _ h: Double, radius r: Double) {
        let r = min(r, w / 2, h / 2)
        cairo_new_sub_path(cr)
        cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
        cairo_arc(cr, x + r, y + h - r, r, Double.pi / 2, Double.pi)
        cairo_arc(cr, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(cr)
    }

    static func isEmojiFlag(_ text: String) -> Bool { isoCode(fromEmojiFlag: text) != nil }

    /// "🇩🇪" → "de": two regional indicator symbols, back to the letters they stand for.
    static func isoCode(fromEmojiFlag text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 2, scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else { return nil }
        return String(scalars.compactMap { Unicode.Scalar($0.value - 0x1F1E6 + 0x61).map(Character.init) })
    }
}
