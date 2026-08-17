# Changelog

All notable changes to WhereAmIP are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow a pragmatic
semver: patch = fixes, minor = features. See also the
[GitHub releases](https://github.com/frinsen/whereamip/releases) for
install-ready notes per version.

## [Unreleased]

### Added
- **E2E VPN test suite** (`scripts/e2e/run.sh`, local-only, opt-in): drives
  real VPN transitions via tailscale/scutil/openvpn/warp-cli/windscribe-cli/networksetup,
  asserts route+DNS behavior, records leak-verdict calibration data, and
  always restores prior network state. Gated XCTest target WhereAmIPE2ETests
  (skipped unless `WHEREAMIP_E2E=1`) checks the live detectors.
- **DNS support**: the dropdown, `whereamip status`, and JSON now show the
  resolvers macOS actually uses (per interface) and whether encrypted DNS
  (DoH/DoT profile) is in force. An active, lightweight egress probe — a TXT
  lookup of a Google-operated beacon (`o-o.myaddr.l.google.com`) sent via
  mDNSResponder on each full refresh, so it sees exactly what real apps'
  lookups do — checks that DNS queries actually exit through the VPN tunnel;
  a leak must survive two consecutive checks before the ⚠️ badge and
  notification fire. `config set dns false` disables the probe entirely (no
  query ever sent) — resolver display stays, since it reads only local
  configuration.
- The IPv6 exit address is now always shown when measured (previously only
  when its country differed from IPv4).
- Version row in Settings.
- **Add to Applications folder** toggle (Settings ▸ Add to Applications folder, and in the
  new first-start window): creates/removes a `/Applications/WhereAmIP.app`
  symlink pointing at the stable brew `opt` path, so the app shows up in
  Spotlight/Launchpad/Finder without the Homebrew formula itself writing
  outside its own prefix — the symlink is only ever created when a user
  clicks the toggle. Also available via `whereamip config set applications
  true|false`; `config get` reports the live on-disk state, not a stored
  preference. Never touches a real (non-symlink) path if one happens to
  already exist there.
- **Welcome window**: shown once on first launch — what the app is, where it
  lives in the menu bar (with a note that notched MacBooks can hide it behind
  the notch), and live-wired Launch at Login / Add to Applications folder /
  Show Notifications checkboxes plus a privacy note. Only clicking
  Done acknowledges it; closing it any other way shows it again next launch.
  Can also be reopened any time via **Settings ▸ Show Welcome Window**.
  - Re-shown on upgrade when a maintainer-controlled `welcomeMilestone`
    constant advances past what a given install last acknowledged (stored as
    `welcomedMilestone`, not a plain "seen it" bool) — lets a future release
    with genuinely notable changes re-surface the window (titled "what's
    new" instead of "Welcome") without pestering on every ordinary upgrade.
  - The notifications checkbox is never pre-checked and never triggers the
    system permission dialog just by the window opening — only a direct
    click can. If notifications were previously denied at the OS level, it
    shows an inline "open Notifications settings" link instead of silently
    re-requesting (which would resolve with no UI and look broken); the
    Settings-menu toggle hits the same previously-denied case by opening
    System Settings directly, since a menu has no inline-hint surface.
  - No other permission prompts, no network calls, from this window.
- Welcome window polish per design review.
- Wording harmonized on "Show Notifications" everywhere (Settings menu row,
  welcome window checkbox) — was "Notify on changes" in the menu and "Notify
  on exit/connectivity changes" in the window; the detail now lives in the
  window's caption instead. `whereamip config get/set notify` is unaffected
  (documented stable CLI key, untouched).

### Fixed
- `whereamip watch` output is now line-buffered when piped or redirected —
  previously the documented `watch --json >> file` logging pattern could
  delay lines by minutes.

## [0.3.2] — 2026-08-17

### Added
- **Restart to finish update**: when `brew upgrade` has already replaced the
  files on disk but the running process is still the old binary, the dropdown
  now shows "↻ Restart to finish update (v…)" instead of re-advertising an
  update the user already installed — one click relaunches into the new
  version via the stable brew `opt` path. Field-motivated: a `brew upgrade`
  left the app telling the user to do something they'd just done.
- **Restart WhereAmIP** menu item, always available above Quit, for a plain
  relaunch of the app independent of the update case.
- The dropdown header and CLI status show the running version
  (`WhereAmIP v0.3.2` in the dropdown; `whereamip status` gets a footer line
  and `--json` gains a top-level `"appVersion"` key), so it's clear at a
  glance which version is active — especially useful alongside the
  restart-to-finish-update row.

### Changed
- "Since"/"Last seen online" timestamps in the dropdown now show a full,
  locale-aware date and time (down to the second), not just a bare `HH:mm` —
  an hours- or days-old state no longer looks identical to a minutes-old one.

## [0.3.1] — 2026-08-17

### Added
- App icon: a mesh flag with a location pin and network route lines. Vector
  source lives in `docs/icon-source.svg`; every `.icns` size is rendered
  straight from the vector for crisp small sizes. Shown in Dock, Finder,
  Cmd-Tab, and the README.

## [0.3] — 2026-08-16

### Added
- **Dual-stack IPv6 leak detection**: IPv4 and IPv6 exits are probed
  independently (stack-pinned lookups via `api4`/`api6.ipify.org` over HTTPS);
  when a VPN owns the v4 route but IPv6 still exits natively and the two
  genuinely differ, a confirmed ⚠️ warning appears in the menu bar (badge),
  dropdown, notifications, and CLI. Attribution works even when the VPN hides
  the native v6 route as an interface-scoped route (field-found PureVPN
  behavior) — the measured v6 address is matched against local interfaces.
- **Quiet update check**: once a day (and on Refresh) the app compares the
  latest GitHub release against itself; when newer, one dropdown row copies
  `brew upgrade whereamip`. On by default, `config set updates false` turns it
  off, the app never downloads or self-updates.
- **Prebuilt download**: releases now attach an unsigned `WhereAmIP.app.zip`
  for non-Homebrew users (right-click-Open or clear quarantine — see release
  notes); Homebrew remains the recommended path.
- Formula gained a `head` spec: `brew install --HEAD whereamip` builds current
  `main`.

### Fixed
- The IPv6 leak rule only ever judges freshly measured exits from the same
  refresh — a stale v4 baseline can never confirm a leak.

## [0.2] — 2026-08-14

### Added
- **Opt-in diagnostics** via Apple unified logging (`os.Logger`, categories
  monitor/geo/route/reducer/relay/update) and a `whereamip debug` subcommand
  that live-streams them; nothing is ever written to disk.

### Fixed
- **False "VPN leak" notification** when switching a VPN on: a probe tick
  landing between the route flip and the geo refresh paired the new route with
  the stale exit IP. Route changes now always escalate to a full refresh, so
  leak detection only judges exit IPs actually fetched through the new route.
- `whereamip watch` gained the 5-minute geo backstop (far-end VPN server
  switches produce no local route event).

## [0.1] — 2026-08-13

Initial release.

### Added
- Country flag of the current exit IP as a native macOS menu bar item
  (AppKit `NSStatusItem`/`NSMenu`), with three display styles: emoji flag,
  ISO country code, flag image.
- Real-reachability probing with hysteresis (catches "Wi-Fi up but traffic
  blackholed"), including detection of OpenVPN's stale `0.0.0.0/1`+`128.0.0.0/1`
  hijack-route pair.
- Route-based VPN awareness: names the VPN that owns the default route via
  SCDynamicStore (never guesses from running apps).
- iCloud Private Relay detection via HTTPS-vs-plain-HTTP dual probe against
  Apple's published relay egress ranges.
- Full CLI: `status [--json]`, `watch [--json]`, `config get/set`, stable JSON
  output.
- Notifications on exit/connectivity changes (off by default), Launch at
  Login, Homebrew tap distribution (`brew tap frinsen/tap`).
