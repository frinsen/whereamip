#ifndef WHEREAMIP_CGTK_SHIM_H
#define WHEREAMIP_CGTK_SHIM_H

// GTK 3 + Ayatana AppIndicator for the Linux panel app. The headers import into Swift as
// they are; the helpers below exist only where Swift cannot follow C on its own — GObject's
// cast macros (GTK_MENU(), GTK_WINDOW(), …), g_signal_connect (a macro), GDK atoms (macros),
// and varargs GVariant construction for the two D-Bus calls the app makes. They stay thin
// on purpose: what to show and when is decided in Swift.

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

// MARK: - signals

static inline gulong wai_connect(gpointer instance, const char *signal, GCallback callback,
                                 gpointer data, GClosureNotify destroy) {
    return g_signal_connect_data(instance, signal, callback, data, destroy, (GConnectFlags)0);
}

// MARK: - menus

static inline GtkWidget *wai_menu_item_new(const char *label) {
    return gtk_menu_item_new_with_label(label);
}

static inline GtkWidget *wai_check_menu_item_new(const char *label, gboolean active, gboolean radio) {
    GtkWidget *item = gtk_check_menu_item_new_with_label(label);
    gtk_check_menu_item_set_draw_as_radio(GTK_CHECK_MENU_ITEM(item), radio);
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), active);
    return item;
}

static inline void wai_menu_append(GtkWidget *menu, GtkWidget *item) {
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
}

static inline void wai_menu_item_set_submenu(GtkWidget *item, GtkWidget *submenu) {
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
}

static inline void wai_menu_item_set_label(GtkWidget *item, const char *label) {
    if (g_strcmp0(gtk_menu_item_get_label(GTK_MENU_ITEM(item)), label) != 0) {
        gtk_menu_item_set_label(GTK_MENU_ITEM(item), label);
    }
}

static inline void wai_check_menu_item_set_active(GtkWidget *item, gboolean active) {
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), active);
}

static inline void wai_indicator_set_menu(AppIndicator *indicator, GtkWidget *menu) {
    app_indicator_set_menu(indicator, GTK_MENU(menu));
}

// MARK: - clipboard

static inline void wai_clipboard_set_text(const char *text) {
    GtkClipboard *clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_text(clipboard, text, -1);
    // Hands the text to a clipboard manager if one runs, so it outlives this process.
    gtk_clipboard_store(clipboard);
}

// MARK: - windows

static inline GtkWidget *wai_window_new(const char *title, int width, int height, const char *icon_name) {
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
    gtk_window_set_icon_name(GTK_WINDOW(window), icon_name);
    gtk_window_set_type_hint(GTK_WINDOW(window), GDK_WINDOW_TYPE_HINT_DIALOG);
    return window;
}

static inline void wai_window_set_resizable(GtkWidget *window, gboolean resizable) {
    gtk_window_set_resizable(GTK_WINDOW(window), resizable);
}

static inline void wai_window_present(GtkWidget *window) {
    gtk_widget_show_all(window);
    gtk_window_present(GTK_WINDOW(window));
}

static inline GtkWidget *wai_box_new(gboolean vertical, int spacing) {
    return gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
}

static inline void wai_box_pack(GtkWidget *box, GtkWidget *child, gboolean expand) {
    gtk_box_pack_start(GTK_BOX(box), child, expand, expand, 0);
}

static inline void wai_box_pack_end(GtkWidget *box, GtkWidget *child) {
    gtk_box_pack_end(GTK_BOX(box), child, FALSE, FALSE, 0);
}

static inline void wai_container_add(GtkWidget *container, GtkWidget *child) {
    gtk_container_add(GTK_CONTAINER(container), child);
}

static inline void wai_set_margins(GtkWidget *widget, int vertical, int horizontal) {
    gtk_widget_set_margin_top(widget, vertical);
    gtk_widget_set_margin_bottom(widget, vertical);
    gtk_widget_set_margin_start(widget, horizontal);
    gtk_widget_set_margin_end(widget, horizontal);
}

/// A wrapping label for reading copy, from Pango markup. Not selectable — prose, not data.
static inline GtkWidget *wai_markup_label_new(const char *markup, float xalign, int max_width_chars) {
    GtkWidget *label = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(label), markup);
    gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
    gtk_label_set_line_wrap_mode(GTK_LABEL(label), PANGO_WRAP_WORD_CHAR);
    gtk_label_set_xalign(GTK_LABEL(label), xalign);
    gtk_label_set_justify(GTK_LABEL(label), xalign == 0.5f ? GTK_JUSTIFY_CENTER : GTK_JUSTIFY_LEFT);
    if (max_width_chars > 0) gtk_label_set_max_width_chars(GTK_LABEL(label), max_width_chars);
    return label;
}

static inline GtkWidget *wai_image_new_from_icon(const char *icon_name, int pixel_size) {
    GtkWidget *image = gtk_image_new_from_icon_name(icon_name, GTK_ICON_SIZE_DIALOG);
    gtk_image_set_pixel_size(GTK_IMAGE(image), pixel_size);
    return image;
}

static inline GtkWidget *wai_scrolled_new(GtkWidget *child) {
    GtkWidget *scrolled = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scrolled), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scrolled), child);
    return scrolled;
}

static inline GtkWidget *wai_check_button_new(const char *label, gboolean active) {
    GtkWidget *button = gtk_check_button_new_with_label(label);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(button), active);
    return button;
}

static inline gboolean wai_toggle_button_get_active(GtkWidget *button) {
    return gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(button));
}

static inline void wai_toggle_button_set_active(GtkWidget *button, gboolean active) {
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(button), active);
}

static inline GtkWidget *wai_button_new(const char *label, gboolean suggested) {
    GtkWidget *button = gtk_button_new_with_label(label);
    if (suggested) {
        gtk_style_context_add_class(gtk_widget_get_style_context(button), "suggested-action");
    }
    return button;
}

static inline void wai_widget_add_css_class(GtkWidget *widget, const char *css_class) {
    gtk_style_context_add_class(gtk_widget_get_style_context(widget), css_class);
}

// MARK: - icon rendering

/// The desktop's own symbolic icon, recoloured to `rgba` — e.g. a white offline glyph for a
/// dark badge. NULL when the theme has no such icon.
static inline GdkPixbuf *wai_load_symbolic_icon(const char *name, int size, double r, double g, double b) {
    GtkIconInfo *info = gtk_icon_theme_lookup_icon(gtk_icon_theme_get_default(), name, size,
                                                   GTK_ICON_LOOKUP_FORCE_SIZE);
    if (!info) return NULL;
    GdkRGBA fg = { r, g, b, 1.0 };
    GdkPixbuf *pixbuf = gtk_icon_info_load_symbolic(info, &fg, NULL, NULL, NULL, NULL, NULL);
    g_object_unref(info);
    return pixbuf;
}

// MARK: - D-Bus

/// org.freedesktop.Notifications.Notify, fire and forget. A desktop without a notification
/// server simply never shows it.
static inline void wai_notify(const char *app_name, const char *icon, const char *summary,
                              const char *body, const char *desktop_entry) {
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus) return;
    GVariantBuilder actions;
    g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
    GVariantBuilder hints;
    g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&hints, "{sv}", "desktop-entry", g_variant_new_string(desktop_entry));
    g_dbus_connection_call(bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                           "org.freedesktop.Notifications", "Notify",
                           g_variant_new("(susssasa{sv}i)", app_name, (guint32)0, icon, summary, body,
                                         &actions, &hints, (gint32)-1),
                           NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL, NULL);
    g_object_unref(bus);
}

/// Whether any panel on this desktop can show an AppIndicator: 1 when a StatusNotifierHost is
/// registered, 0 when the watcher runs but no host has registered, -1 when there is no
/// watcher at all (which is how elementary OS's stock panel answers).
static inline int wai_status_notifier_host_state(void) {
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus) return -1;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
        "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", "org.kde.StatusNotifierWatcher", "IsStatusNotifierHostRegistered"),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, NULL);
    g_object_unref(bus);
    if (!reply) return -1;
    GVariant *boxed = NULL;
    g_variant_get(reply, "(v)", &boxed);
    int state = (boxed && g_variant_is_of_type(boxed, G_VARIANT_TYPE_BOOLEAN) && g_variant_get_boolean(boxed)) ? 1 : 0;
    if (boxed) g_variant_unref(boxed);
    g_variant_unref(reply);
    return state;
}

/// Whether an X11 system tray (the XEmbed protocol libayatana-appindicator falls back to
/// when no StatusNotifierItem host exists) is running on this display.
static inline gboolean wai_xembed_tray_present(void) {
#ifdef GDK_WINDOWING_X11
    GdkDisplay *display = gdk_display_get_default();
    if (!display || !GDK_IS_X11_DISPLAY(display)) return FALSE;
    Display *xdisplay = GDK_DISPLAY_XDISPLAY(display);
    int screen = XDefaultScreen(xdisplay);
    char name[64];
    g_snprintf(name, sizeof name, "_NET_SYSTEM_TRAY_S%d", screen);
    Atom selection = XInternAtom(xdisplay, name, False);
    return XGetSelectionOwner(xdisplay, selection) != None;
#else
    return FALSE;
#endif
}

typedef void (*wai_resume_callback)(gpointer data);

typedef struct {
    wai_resume_callback callback;
    gpointer data;
} wai_resume_watch;

static inline void wai__prepare_for_sleep(GDBusConnection *connection, const gchar *sender,
                                          const gchar *path, const gchar *interface,
                                          const gchar *signal, GVariant *parameters, gpointer user_data) {
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal;
    gboolean going_to_sleep = TRUE;
    g_variant_get(parameters, "(b)", &going_to_sleep);
    if (!going_to_sleep) {
        wai_resume_watch *watch = (wai_resume_watch *)user_data;
        watch->callback(watch->data);
    }
}

/// Calls `callback` on the main loop each time the machine resumes from suspend
/// (logind's PrepareForSleep(false)) — the Linux side of NSWorkspace.didWakeNotification.
static inline void wai_watch_resume(wai_resume_callback callback, gpointer data) {
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, NULL);
    if (!bus) return;
    wai_resume_watch *watch = g_new0(wai_resume_watch, 1);
    watch->callback = callback;
    watch->data = data;
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
                                       "PrepareForSleep", "/org/freedesktop/login1", NULL,
                                       G_DBUS_SIGNAL_FLAGS_NONE, wai__prepare_for_sleep, watch, g_free);
    // The connection is a process-wide singleton; the subscription keeps it alive.
}

#endif
