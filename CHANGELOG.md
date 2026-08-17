# Changelog

All notable changes to WhereAmIP are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow a pragmatic
semver: patch = fixes, minor = features. See also the
[GitHub releases](https://github.com/frinsen/whereamip/releases) for
install-ready notes per version.

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
