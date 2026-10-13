import CGtk
import Foundation
import WhereAmIPCore
import WhereAmIPUI
import WhereAmIPLinuxUI

/// The help window: the Linux help copy, rendered once, in a scrolling label.
final class HelpWindow {
    private(set) var window: UnsafeMutablePointer<GtkWidget>?

    init() {
        let window = wai_window_new(L10n.string(.helpWindowTitle), 600, 680, LinuxDesktopEntry.id)!
        let label = wai_markup_label_new(PangoMarkup.render(markdown: LinuxContent.helpMarkdown()), 0, 72)!
        wai_set_margins(label, 20, 24)
        wai_container_add(window, wai_scrolled_new(label))
        connect(UnsafeMutableRawPointer(window), "destroy") { [weak self] in self?.window = nil }
        self.window = window
    }

    var isOpen: Bool { window != nil }
    func present() { if let window { wai_window_present(window) } }
}

/// The first-run window: what the app is, where it lives, and the three integrations as
/// live toggles — the macOS welcome window's layout, with Linux's integrations behind the
/// toggles (autostart entry, applications-menu entry, desktop notifications).
final class WelcomeWindow {
    struct Toggle {
        let label: String
        let isOn: () -> Bool
        let set: (Bool) -> Void
    }

    private(set) var window: UnsafeMutablePointer<GtkWidget>?
    private var buttons: [(widget: UnsafeMutablePointer<GtkWidget>, toggle: Toggle)] = []
    private var syncing = false

    init(toggles: [Toggle], showsTrayHint: Bool, onDone: @escaping () -> Void) {
        // The intro variant's heading (the running version), over the Linux intro copy.
        let heading = L10n.string(.welcomeHeading, whereamipVersion)
        let window = wai_window_new(L10n.string(.welcomeWindowTitle), 460, -1, LinuxDesktopEntry.id)!
        let box = wai_box_new(1, 10)!
        wai_set_margins(box, 22, 28)

        if gtk_icon_theme_has_icon(gtk_icon_theme_get_default(), LinuxDesktopEntry.id) != 0 {
            wai_box_pack(box, wai_image_new_from_icon(LinuxDesktopEntry.id, 72), 0)
        }
        let badge = PangoMarkup.escape(L10n.string(.welcomeBadgeIntro).uppercased())
        wai_box_pack(box, wai_markup_label_new("<small><b>\(badge)</b></small>", 0.5, 50), 0)
        wai_box_pack(box, wai_markup_label_new("<span size=\"x-large\"><b>\(PangoMarkup.escape(heading))</b></span>",
                                               0.5, 50), 0)
        wai_box_pack(box, wai_markup_label_new(PangoMarkup.render(markdown: LinuxContent.welcomeMarkdown()), 0.5, 52), 0)
        if showsTrayHint {
            let hint = wai_markup_label_new("<small>\(PangoMarkup.escape(L10n.string(.welcomeTrayHint)))</small>", 0.5, 56)!
            wai_widget_add_css_class(hint, "dim-label")
            wai_box_pack(box, hint, 0)
        }

        let header = PangoMarkup.escape(L10n.string(.welcomeSetupHeader).uppercased())
        let caption = PangoMarkup.escape(L10n.string(.welcomeSetupCaption))
        let setup = wai_markup_label_new("<small><b>\(header)</b>\n\(caption)</small>", 0, 56)!
        gtk_widget_set_margin_top(setup, 8)
        wai_box_pack(box, setup, 0)
        for toggle in toggles {
            let button = wai_check_button_new(toggle.label, toggle.isOn() ? 1 : 0)!
            buttons.append((button, toggle))
            wai_box_pack(box, button, 0)
            connect(UnsafeMutableRawPointer(button), "toggled") { [weak self] in self?.toggled(button) }
        }

        let privacy = wai_markup_label_new("<small>\(PangoMarkup.escape(L10n.string(.welcomePrivacy)))</small>", 0.5, 56)!
        wai_widget_add_css_class(privacy, "dim-label")
        gtk_widget_set_margin_top(privacy, 8)
        wai_box_pack(box, privacy, 0)
        let done = wai_button_new(L10n.string(.welcomeDone), 1)!
        gtk_widget_set_halign(done, GTK_ALIGN_END)
        connect(UnsafeMutableRawPointer(done), "clicked") { [weak self] in
            onDone()
            if let window = self?.window { gtk_widget_destroy(window) }
        }
        wai_box_pack(box, done, 0)

        wai_container_add(window, box)
        // Fixed to its content, like the macOS window: a resizable GTK window sizes wrapping
        // labels for their narrowest width and leaves the slack as dead space at the bottom.
        wai_window_set_resizable(window, 0)
        connect(UnsafeMutableRawPointer(window), "destroy") { [weak self] in self?.window = nil }
        self.window = window
    }

    var isOpen: Bool { window != nil }
    func present() { if let window { wai_window_present(window) } }

    /// Applies the click, then shows what is actually true — a toggle whose change failed
    /// (an entry WhereAmIP did not create, say) springs back rather than lying.
    private func toggled(_ widget: UnsafeMutablePointer<GtkWidget>) {
        guard !syncing, let toggle = buttons.first(where: { $0.widget == widget })?.toggle else { return }
        let wanted = wai_toggle_button_get_active(widget) != 0
        if wanted != toggle.isOn() { toggle.set(wanted) }
        syncFromTruth()
    }

    func syncFromTruth() {
        syncing = true
        defer { syncing = false }
        for (widget, toggle) in buttons { wai_toggle_button_set_active(widget, toggle.isOn() ? 1 : 0) }
    }
}
