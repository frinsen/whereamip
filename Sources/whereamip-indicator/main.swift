import CGtk
import Foundation
import Glibc
import WhereAmIPCore

// WhereAmIP for Linux desktops: the panel indicator. The macOS app's AppKit status item
// becomes an Ayatana AppIndicator (StatusNotifierItem), which GNOME (with its AppIndicator
// extension), KDE, Cinnamon, MATE, Xfce, Budgie — and elementary OS with the AppIconTray
// indicator — show in their panel.

setlocale(LC_ALL, "")

// X11 first, through XWayland on a Wayland session. The indicator itself is D-Bus and does
// not care; the clipboard does — a Wayland client may only set it while it has keyboard
// focus, and a panel menu is drawn by the panel, so this app never has focus when a copy
// row is clicked. An X11 client may always own the CLIPBOARD selection, and the compositor
// hands it on to Wayland apps.
gdk_set_allowed_backends("x11,*")
g_set_application_name("WhereAmIP")

guard gtk_init_check(nil, nil) != 0 else {
    FileHandle.standardError.write(Data(("whereamip-indicator: no graphical session to show a panel icon in. "
        + "The whereamip command works without one.\n").utf8))
    exit(1)
}

guard InstanceLock.acquire() else {
    Log.instance.notice("guard: another whereamip-indicator is already running — leaving")
    exit(0)
}

let app = IndicatorApp()
app.start()
gtk_main()
