import CGtk
import Foundation
import WhereAmIPLinuxUI

/// Turns a `MenuItemModel` tree into the GtkMenu the indicator exports to the panel.
///
/// The menu is rebuilt only when its STRUCTURE changes (a row appears or goes away). When
/// only text or checkmarks change — "Checked" ticking over every 30 seconds, a toggle the
/// user just flipped — the existing rows are updated in place, which the panel receives as
/// property changes on an open menu rather than a new menu swapped in under the pointer.
/// That is the same lesson the macOS `MenuTrackingSession` encodes: never tear an open
/// menu's rows out from under the reader.
final class MenuRenderer {
    private let indicator: UnsafeMutablePointer<AppIndicator>
    private let perform: (MenuAction) -> Void
    private var structure: String?
    private var widgets: [String: UnsafeMutablePointer<GtkWidget>] = [:]
    private var actions: [String: MenuAction] = [:]
    /// `gtk_check_menu_item_set_active` emits "activate" like a click does; updates made
    /// here must not be mistaken for the user choosing something.
    private var isUpdating = false

    init(indicator: UnsafeMutablePointer<AppIndicator>, perform: @escaping (MenuAction) -> Void) {
        self.indicator = indicator
        self.perform = perform
    }

    func render(_ items: [MenuItemModel]) {
        isUpdating = true
        defer { isUpdating = false }
        let newStructure = items.structure
        if newStructure == structure {
            update(items, path: "")
        } else {
            widgets = [:]
            actions = [:]
            let menu = gtk_menu_new()!
            build(items, into: menu, path: "")
            gtk_widget_show_all(menu)
            wai_indicator_set_menu(indicator, menu)
            structure = newStructure
        }
    }

    private func build(_ items: [MenuItemModel], into menu: UnsafeMutablePointer<GtkWidget>, path: String) {
        for item in items {
            let key = path + item.id
            let widget: UnsafeMutablePointer<GtkWidget>
            switch item.kind {
            case .separator:
                widget = gtk_separator_menu_item_new()
            case .info:
                widget = wai_menu_item_new(item.title)
                gtk_widget_set_sensitive(widget, 0)
            case .action(let action):
                widget = wai_menu_item_new(item.title)
                actions[key] = action
                hook(widget, key)
            case .toggle(let isOn, let radio, let action):
                widget = wai_check_menu_item_new(item.title, isOn ? 1 : 0, radio ? 1 : 0)
                actions[key] = action
                hook(widget, key)
            case .submenu(let children):
                widget = wai_menu_item_new(item.title)
                let submenu = gtk_menu_new()!
                build(children, into: submenu, path: key + "/")
                wai_menu_item_set_submenu(widget, submenu)
            }
            widgets[key] = widget
            wai_menu_append(menu, widget)
        }
    }

    private func update(_ items: [MenuItemModel], path: String) {
        for item in items {
            let key = path + item.id
            guard let widget = widgets[key] else { continue }
            switch item.kind {
            case .separator:
                break
            case .info:
                wai_menu_item_set_label(widget, item.title)
            case .action(let action):
                wai_menu_item_set_label(widget, item.title)
                actions[key] = action
            case .toggle(let isOn, _, let action):
                wai_menu_item_set_label(widget, item.title)
                wai_check_menu_item_set_active(widget, isOn ? 1 : 0)
                actions[key] = action
            case .submenu(let children):
                wai_menu_item_set_label(widget, item.title)
                update(children, path: key + "/")
            }
        }
    }

    /// The handler looks its action up at click time, so a row updated in place always runs
    /// the action of the state it is currently showing (a copy row copies the current IP).
    private func hook(_ widget: UnsafeMutablePointer<GtkWidget>, _ key: String) {
        connect(UnsafeMutableRawPointer(widget), "activate") { [weak self] in
            guard let self, !self.isUpdating, let action = self.actions[key] else { return }
            // Out of the signal handler first: acting may re-render this very menu.
            MainThread.async { self.perform(action) }
        }
    }
}
