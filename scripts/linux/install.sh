#!/usr/bin/env bash
# Builds WhereAmIP from source and installs it for the current user — no sudo, nothing
# written outside $PREFIX (default ~/.local):
#
#   $PREFIX/lib/whereamip/                 whereamip, whereamip-indicator and their resources
#   $PREFIX/bin/whereamip                  -> the CLI
#   $PREFIX/bin/whereamip-indicator        -> the panel app
#   $PREFIX/share/icons/hicolor/256x256/apps/io.github.frinsen.whereamip.png
#   ~/.local/share/applications/io.github.frinsen.whereamip.desktop   (applications menu)
#
# Usage:
#   scripts/linux/install.sh               build, install, add the menu entry, start it
#   scripts/linux/install.sh --no-start    same, without starting the panel app
#   scripts/linux/install.sh --uninstall   remove everything above (settings stay)
#
# Re-running it upgrades in place. A copy that is already running notices its files were
# replaced and offers "Restart to finish update" in its menu.
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
LIB="$PREFIX/lib/whereamip"
BIN="$PREFIX/bin"
ICON_DIR="$PREFIX/share/icons/hicolor/256x256/apps"
APP_ID="io.github.frinsen.whereamip"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

start=1
uninstall=0
for arg in "$@"; do
    case "$arg" in
        --no-start) start=0 ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Whether a panel app is running for this user: its single-instance lock is held. (Not
# pgrep -x: the kernel truncates process names to 15 characters.)
running() {
    local lock="${XDG_RUNTIME_DIR:-/tmp}/whereamip-indicator-$(id -u).lock"
    [ -e "$lock" ] && ! flock -n "$lock" true 2>/dev/null
}

if [ "$uninstall" = 1 ]; then
    # The CLI removes the desktop entries it manages (and only those).
    if [ -x "$LIB/whereamip" ]; then
        "$LIB/whereamip" config set applications false 2>/dev/null || true
    fi
    autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/$APP_ID.desktop"
    if [ -f "$autostart" ] && grep -qx 'X-WhereAmIP-Managed=true' "$autostart"; then
        rm -f "$autostart"
    fi
    pkill -u "$(id -u)" -f "$LIB/whereamip-indicator" 2>/dev/null || true
    rm -rf "$LIB"
    rm -f "$BIN/whereamip" "$BIN/whereamip-indicator" "$ICON_DIR/$APP_ID.png"
    say "WhereAmIP removed. Settings stay in ~/.config/$APP_ID.plist — delete it to forget them too."
    exit 0
fi

# --- preflight ---------------------------------------------------------------------------

if ! command -v swift >/dev/null 2>&1; then
    cat >&2 <<'EOF'
WhereAmIP builds from source and needs a Swift toolchain (5.9 or newer). The official
installer, swiftly, sets one up in your home directory (see https://swift.org/install/linux/):

    curl -O "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
    tar zxf "swiftly-$(uname -m).tar.gz"
    ./swiftly init --quiet-shell-followup
    . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && hash -r

swiftly lists any system packages it still needs. Then run this script again.
EOF
    exit 1
fi

missing=()
for module in gtk+-3.0 ayatana-appindicator3-0.1; do
    pkg-config --exists "$module" 2>/dev/null || missing+=("$module")
done
if [ "${#missing[@]}" -gt 0 ]; then
    cat >&2 <<EOF
Missing development files for: ${missing[*]}
On Ubuntu, elementary OS, Linux Mint, Pop!_OS and Debian:

    sudo apt install libgtk-3-dev libayatana-appindicator3-dev

Then run this script again.
EOF
    exit 1
fi

# --- build ---------------------------------------------------------------------------------

say "Building (release) — the first build takes a few minutes"
cd "$REPO"
# Static Swift runtime: the installed binaries keep working whatever happens to the
# toolchain later (upgraded, moved, removed). They then depend on system libraries only.
swift build -c release --static-swift-stdlib
OUT="$(swift build -c release --static-swift-stdlib --show-bin-path)"

# --- install -------------------------------------------------------------------------------

say "Installing into $LIB"
mkdir -p "$LIB" "$BIN" "$ICON_DIR"
# `install` replaces each file with a new one rather than writing into it: a running copy
# keeps its old inode, which is exactly how it notices an update is waiting.
install -m 755 "$OUT/whereamip" "$OUT/whereamip-indicator" "$LIB/"
for bundle in "$OUT"/whereamip_*.resources; do
    rm -rf "$LIB/$(basename "$bundle")"
    cp -R "$bundle" "$LIB/"
done
ln -sfn "$LIB/whereamip" "$BIN/whereamip"
ln -sfn "$LIB/whereamip-indicator" "$BIN/whereamip-indicator"
install -m 644 "$REPO/docs/icon-256.png" "$ICON_DIR/$APP_ID.png"
command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

# The applications-menu entry, written by the CLI so it is the same managed entry the
# panel menu's "Show in Applications Menu" toggle manages.
"$LIB/whereamip" config set applications true \
    || say "Could not add the applications-menu entry (an entry WhereAmIP did not create is in the way)."

say "Installed $("$LIB/whereamip" --version) — try: whereamip status"
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) say "Note: $BIN is not on your PATH yet; log out and back in, or add it to your shell profile." ;;
esac

# --- the panel -----------------------------------------------------------------------------

# Panels show app icons through StatusNotifierItem. elementary OS's panel does not by
# default — say so now rather than leaving an invisible app.
if command -v gdbus >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}${XDG_RUNTIME_DIR:-}" ]; then
    has_watcher="$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.kde.StatusNotifierWatcher 2>/dev/null || true)"
    if [ "$has_watcher" = "(false,)" ]; then
        if [[ "${XDG_CURRENT_DESKTOP:-}" == *Pantheon* ]]; then
            say "elementary OS: the panel needs the AppIconTray indicator to show WhereAmIP's flag."
            say "Install it from https://github.com/barunespadhy/wingpanel-indicator-appicontray (see README)."
        else
            say "This desktop's panel shows no app indicators yet (GNOME: install the AppIndicator extension)."
        fi
    fi
fi

if [ "$start" = 1 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if running; then
        say "WhereAmIP is already running — use Restart WhereAmIP in its menu to switch to this build."
    else
        say "Starting the panel app — the first-start window offers Launch at Login."
        nohup "$LIB/whereamip-indicator" >/dev/null 2>&1 &
    fi
fi
