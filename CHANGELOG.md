# Changelog

All notable changes to WhereAmIP are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow a pragmatic
semver: patch = fixes, minor = features. See also the
[GitHub releases](https://github.com/frinsen/whereamip/releases) for
install-ready notes per version.

## [Unreleased]

## [0.5.5] — 2026-08-24

### Added
- **A language picker in Settings.** The app still follows your Mac by default, but
  Settings ▸ Language now switches it by hand — System Language, English, or Deutsch —
  and the change is live: the next time you open the menu it is in the new language, with
  no restart. `whereamip config set language de|en|system` does the same from the CLI and
  `config get` reports it. (The CLI's own output stays English either way — it is a
  parseable interface, not UI.) A welcome or help window that is already open keeps the
  language it was opened with until you reopen it.
- **Deutsch.** The app now follows your Mac's language: every dropdown row, notification,
  and both windows (welcome and help) are available in German, including the long-form
  help and what's-new copy. English stays the default everywhere else. `whereamip`
  output, `whereamip diagnostics` and the log are deliberately not translated — they are
  a parseable interface, and reports written from them land in English-language issues.
- The help window's closing GitHub pointer is a real link now: click it and the browser
  opens. The help body moved from a text field to a non-editable text view to make that
  possible, which also lets you select and copy any part of the help text.

### Changed
- The update check now also rides along with a full refresh, at most once every six
  hours, instead of relying on the daily timer alone. A release published just after that
  timer ran could stay invisible for up to a day (which is how a beta tester ended up on
  an old version); worst case is now a few hours. Costs roughly two or three extra
  requests a day, and the "Check for Updates" setting still means no request is ever made
  when it is off.

### Fixed
- The update row now copies `brew update && brew upgrade whereamip`, not the bare
  upgrade. WhereAmIP installs from a third-party tap, which Homebrew keeps as a git
  clone that `brew upgrade <formula>` does not reliably pull — so on a stale clone the
  upgrade reported the version you already had and did nothing. Reported from the field:
  "0.4.2 already installed", hours after 0.5 was on the tap. The row also stops spelling
  the command out (it named an incomplete one, which is how the trap was set); it now
  says it copies the update command, and the clipboard carries the whole thing.
- The open dropdown no longer jumps when you hold or release ⌥. Two causes, both fixed:
  the app rebuilt every row on each keydown during menu tracking (AppKit calls
  `menuNeedsUpdate` there, modifier presses included), tearing the item views out from
  under the cursor — the menu is now built once per open, and the ⌥ alternate swaps
  natively, as it was always meant to. And the menu got ~14pt wider while ⌥ was held,
  because the shared key-equivalent column has to fit ⌥⌘C instead of ⌘C; since a menu bar
  menu is anchored at its right edge, that pushed the left edge outward. The build now
  reserves the wider of the two states up front, so the swap is pixel-stable. A state
  refresh that lands while the menu is open now appears on the next open rather than
  rearranging rows mid-click.

## [0.5] — 2026-08-24

### Added
- **DNS egress enumeration**: the leak check now discovers *all* of your
  egress resolvers instead of one. Public resolvers are load-balanced across
  a pool, so a single lookup only ever reveals whichever member answered it;
  a full refresh now fires a round of six TXT lookups of random, single-use
  names under `test.dnscheck.tools` (an authoritative server that reports who
  asked — the dnsleaktest.com mechanism), which typically surfaces both an
  IPv4 and an IPv6 egress of the same operator. Each discovered resolver
  carries its operator, location, and transport (UDP/TCP/TLS). The Google
  `o-o.myaddr.l.google.com` beacon remains as the fallback when that service
  is unreachable, and `config set dns false` still disables every query.
- The dropdown's DNS row is now a submenu: "Configured resolvers" (each
  unique address once, with the interfaces it was scoped to) above "Queries
  answered by" (every discovered egress resolver). `whereamip status` shows
  the same egress resolvers on an indented line, and `--json` gains a
  `dns.egressResolvers` array — additive, absent from older output.
- When every configured resolver is router-local but the queries surface at a
  known public provider, the submenu names it: "Router forwards to Quad9 —
  encryption of that hop is set on the router". An attribution hint only —
  the client cannot observe whether that hop is encrypted, and forwarding is
  normal configuration, so this never warns. "Router-local" means a private
  range, an address inside one of this host's directly connected prefixes
  (which is how a router advertising itself with a *global* address out of
  the ISP's delegated prefix is recognized — no vendor or ISP knowledge
  involved), or the same box in a prefix the ISP has since rotated away
  (identical IPv6 interface identifier as an already-anchored resolver).
- **Copy Diagnostics** (⌘D, first row above Refresh): puts the whole dropdown
  on the clipboard as plain text — version, exit, IPv6 exit, route, Since,
  configured resolvers, answering resolvers — with every warning the dropdown is
  currently showing (offline, OpenVPN hijack routes while offline, confirmed
  IPv6 leak, DNS leak confirmed or suspected) called out on its own labelled
  line at the top. It warns about exactly what the app itself is warning about
  and nothing more: leftover hijack routes on a *working* connection are noted
  as a neutral fact on the Route line instead ("· hijack pair (0/1 + 128/1)
  present"), and the two leak verdicts — which are deliberately carried over
  rather than re-measured while offline — are not asserted in an offline report.
  Paste it into a bug report. It writes to the local clipboard, sends nothing
  anywhere, and collects nothing new. `whereamip diagnostics` prints exactly the
  same text; `status`, `watch`, `config`, and the JSON are unchanged.
- **⌥⌘C copies both exit addresses.** Hold ⌥ with the dropdown open and the
  exit-IP row turns into "Copy both exit addresses" — IPv4 and IPv6, one per
  line, addresses only. When there is no IPv6 exit to copy, holding ⌥ says
  exactly that instead of leaving you wondering where the copy went. Plain ⌘C
  on the IP row is unchanged.
- **Bulk copy in the DNS submenu**: "Copy configured resolvers" and "Copy
  answering resolvers" at its foot, each copying bare addresses one per line —
  no interface suffixes, operator names, locations, or transports. The
  answering row is absent when the DNS check is off or nothing has answered
  yet.
- **WhereAmIP Help** (⌘?, directly above Settings) opens a help window: what
  the menu bar symbol means, Since vs Checked, how to read the DNS submenu, the
  keyboard shortcuts, and the CLI. The app is a menu bar accessory with no menu
  bar of its own, so this row stands in for the Help menu. The welcome window is
  unaffected and the two can be open at the same time.
- **User-facing texts are out of the code.** Every string the menu bar app shows
  — dropdown rows, warning lines, the DNS submenu, Settings items, notification
  titles/bodies, the welcome window — now comes from
  `Sources/WhereAmIPUI/Resources/en.lproj/Localizable.strings`, looked up by
  stable hierarchical keys (`menu.*`, `settings.*`, `dns.*`, `notification.*`,
  `welcome.*`). Wording can be retuned for a release by editing that one file;
  the UI tests assert against the lookups, not against literals, so retuning
  doesn't break the suite. English only for now — a `de.lproj` beside it is all
  a translation needs. `whereamip status`/`watch`/`--json` output is deliberately
  untouched: it's a parseable API, not copy.
- **Welcome window content is bundled Markdown**, one file per milestone under
  `Sources/WhereAmIPUI/Resources/welcome/`. First launch renders `intro.md`; a
  `welcomeMilestone` re-trigger renders that milestone's real highlights from
  `<milestone>.md` — titled with the milestone version rather than the running
  one — instead of repeating the first-run pitch. A milestone with no file falls
  back to the intro copy. Rendering covers paragraphs, bullets and inline
  emphasis, with no new dependency; the window sizes to its content once at open
  and never resizes live.
- An unnamed tunnel explains itself in the diagnostics report: a line under Route
  stating that no service name was found, that no address or process tell matched,
  and which known VPN apps were running (the input to the ambiguity guard). If your
  VPN shows as "VPN (utunN)", that line is what an issue needs in order to add it.

### Changed
- The DNS leak verdict is now measured from the enumeration's primary
  (IPv4-first) egress resolver rather than the Google beacon's answer; the
  verdict logic itself, including the two-consecutive-refresh confirmation
  and the org/ASN rescue, is unchanged. A confirmed leak row can now name
  the egress operator from the enumeration data when the geo attribution
  lookup fails — no additional lookup was added.
- **Truthful VPN naming.** A tunnel WhereAmIP can't identify now reads "VPN (utun4)"
  instead of "VPN: unknown (utun4)" — it is a real tunnel owning a real route, and
  only the brand is missing, so the row says that rather than reading like a
  malfunction. Naming from the macOS network service a client registers is unchanged
  and remains the vendor-neutral path that works for clients this app has never heard
  of.
- The Tailscale fingerprint now needs corroboration. A 100.64/10 source address alone
  no longer means Tailscale: that is RFC 6598 carrier-grade NAT — public space any
  mesh VPN (Headscale, NetBird, Nebula) or a CGNAT'd uplink may use — so it names
  Tailscale only alongside Tailscale's own bundle id or a visible Tailscale process.
  Uncorroborated, it falls through to the rest of the ladder instead of guessing.
  Cloudflare WARP's 172.16.0.2 keeps needing no corroboration: that constant is
  assigned by WARP's own client, so it identifies the vendor by construction.
- OpenVPN Connect tunnels are named again. The old check looked for the `ovpnagent`
  daemon, which runs as root and is therefore invisible to an unprivileged process
  scan — dead code that could never fire, leaving the tunnel unnamed. It now also
  matches the user-owned "OpenVPN Connect" processes that the scanner really sees.

### Fixed
- IPv6-only route changes now escalate a probe tick into a full refresh. A VPN that
  tunnels only IPv4 while the native IPv6 default route appears mid-session (delayed
  router advertisement, a re-attached cable) applied the new route next to an IPv6
  exit measured before it existed — so an IPv6 leak stayed invisible until the next
  scheduled full refresh, up to five minutes later.
- Malformed IPv4 strings are rejected instead of being silently repaired. The parser
  dropped unparseable components, so "999.1.2.3.4" became 1.2.3.4 — and since that
  parser is what decides "is this an address at all" for DNS egress answers arriving
  off the network, a malformed or spoofed answer could be judged a real egress and
  produce a false DNS-leak warning out of garbage.
- A confirmed DNS-leak alarm is now lowered when Tailscale's MagicDNS resolver later
  appears in the configured set (switching on "Override local DNS" after a
  confirmation). The documented policy for that case is "never confirms, never
  notifies"; previously an already-lit ⚠️ stayed lit forever.
- A full refresh that coalesces onto a probe tick which then escalates is satisfied by
  that escalation instead of running a second, fully redundant refresh — it was
  repeating every geo, DNS and relay call the escalation had just made.
- Reopening the Welcome or Help window while it is already open now brings that window
  forward instead of building a second one behind it. The old window stayed on screen
  but its controller was released, leaving its buttons inert — a visibly dead Done
  button.
- The release workflow is idempotent: a rerun skips creating a release that already
  exists and re-uploads assets with `--clobber`, so a half-finished release (as
  happened when GitHub 503'd during v0.4.2) can be completed by rerunning it.

## [0.4.2] — 2026-08-17

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
- Connection kind (Wi-Fi/Ethernet/iPhone USB) shown for the active route,
  derived from the system via `SCNetworkInterface` rather than guessed.
- A generic "IKEv2 VPN" label for native NE personal VPN (IKEv2/IPsec)
  interfaces that otherwise expose no name anywhere reachable — used only as
  a last-resort fallback, never shadowing a real detected name.
- Classic OpenVPN daemon tunnels (`ovpnagent`/`openvpn`, no SCDynamicStore
  presence at all) are now named "OpenVPN" from running-process evidence,
  instead of being misnamed by whichever known VPN app's bundle happens to
  sort first in the table.
- Confirmed DNS-leak rows in the dropdown and `whereamip status` now name
  the resolver's egress operator when it's known: "queries answered via
  Cloudflare, Inc. (2400:cb00:…)" instead of just the bare IP.

### Changed
- The bundle-ID VPN-name table only names a tunnel when exactly one known
  VPN app is running; two or more known apps running at once now show no
  name instead of guessing by table order.
- Tailscale MagicDNS setups (resolver `100.100.100.100` present) cap the
  DNS-leak verdict at "suspected" — never "confirmed", never a notification:
  a mismatched egress can't be distinguished from MagicDNS's own intentional
  delegation to a user-configured upstream, so the app declines to accuse.
  (Known limit: while MagicDNS is present, an unrelated genuine leak is also
  held at "suspected" — visible in the dropdown/CLI, but not notified.)
- DNS-leak verdicts now recognize the VPN provider's own resolvers: when a
  resolver's egress IP is attributed — by ASN, or by an exact org-string
  match sourced from the same geo provider as the tunnel exit — to the same
  network operator as the tunnel exit, the verdict is ruled "none" instead
  of "suspected"/"confirmed". When a comparison was possible but could not
  be evaluated — the tunnel exit carries an ASN/org, but the egress lookup
  failed — a suspected leak now stays "suspected" in the dropdown/CLI
  rather than advancing to the confirmed badge/notification: it never
  confirms on a failed lookup when the rescue check was still owed. When no
  comparison was ever possible (neither side attributed), behavior is
  unchanged from before.

### Fixed
- `whereamip watch` output is now line-buffered when piped or redirected —
  previously the documented `watch --json >> file` logging pattern could
  delay lines by minutes.
- DNS row's "+N more" count now reflects unique resolver **addresses**, not
  raw model entries — `DNSConfigReader.parse` intentionally keeps a global
  entry plus one per-service entry per address (for leak-detector
  attribution), which was inflating the dropdown/CLI count (e.g. "+11 more"
  for 4 actual addresses).
- NE-based app VPNs (e.g. Tailscale's `utun16`) now get their real service
  name: they only register `InterfaceName` under the IPv6/DNS State keys,
  never IPv4, so the old IPv4-only key scan silently returned no name for
  every one of them.
- Settings submenu no longer shows its own "WhereAmIP v<version>" row — the
  main dropdown header already carries it, and a submenu re-branding itself
  isn't native macOS menu style.
- Settings toggle "Check DNS egress" renamed to "Check for DNS Leaks" —
  matches the wording of the sibling "Check for Updates" toggle and the
  vocabulary already used by the DNS leak warning row.

## [0.4.1] — 2026-08-17

### Fixed
- **Restart/relaunch could silently drop the new instance.** Field bug from
  the first real 0.3.2→0.4 upgrade: clicking "↻ Restart to finish update" (or
  plain "Restart WhereAmIP") terminated the running process but the new one
  sometimes never launched — zero `whereamip` processes left afterward. The
  old mechanism fired `open -n <path>` and then called `NSApp.terminate`
  after a fixed 0.5s delay; that delay was a race, not a synchronization —
  if this process (same bundle ID as the one being launched) died while
  Launch Services was still mid-handshake on the pending launch, LS could
  coalesce/abort it. Replaced with a detached waiter that polls for this
  process's PID to actually disappear before running `open`, then terminates
  immediately with no arbitrary delay — closing the race window entirely.
- **Welcome window's Show Notifications checkbox could disagree with
  Settings.** Reopening the welcome window (Settings ▸ Show Welcome Window)
  with notifications already enabled showed the checkbox unchecked, directly
  under a header claiming "reflects current settings". The original
  "never pre-checked" rule was written for first-run only (where the setting
  is always off anyway) and stopped being true the moment the window became
  reopenable. Now mirrors `notificationsEnabled` like its two sibling
  checkboxes, with one refinement: if the OS-level permission has actually
  been denied, it shows unchecked regardless of the stored setting (an
  enabled setting that can't deliver anything is honestly "off"), alongside
  the existing denied-hint. The permission dialog still only ever appears as
  a direct result of actively checking the box from off.
- **Notification banners and System Settings showed a placeholder icon**,
  even after a full cache reset. `AppIcon.icns` alone (`CFBundleIconFile`)
  isn't enough — the notification subsystem on this macOS specifically looks
  for `CFBundleIconName` resolved via a compiled asset catalog, which the
  app bundle never shipped. Added the modern icon path: `docs/Assets.car`,
  compiled once at dev time (`scripts/update-appicon.sh`, requires full
  Xcode's `actool` — not available in Homebrew's Command-Line-Tools-only
  build environment) and committed alongside `AppIcon.icns`;
  `make-app-bundle.sh` only ever copies the committed file, never compiles
  it, so `brew install` is unaffected. Both `CFBundleIconFile` and the new
  `CFBundleIconName` are set in Info.plist — belt and suspenders, since
  older subsystems still read the `.icns` directly.
- **Manual refresh's loading cue shifted every neighboring menu bar icon.**
  The "…" swap that replaced the glyph during a manual refresh changed the
  status item's width, so surrounding icons visibly jumped left and back —
  same disease class as the earlier welcome-window layout jump. Manual
  refresh now dims the menu bar icon (native `NSStatusBarButton
  .appearsDisabled`, the same mechanism system status items use to show
  "busy") instead of swapping it — zero width change, still visible
  feedback.

### Changed
- Dropdown header row shows the app icon instead of the exit-country flag
  emoji (which was redundant there — the flag is already the menu *bar*
  glyph directly above the dropdown); title is now plain "WhereAmIP v<version>".

## [0.4] — 2026-08-17

### Added
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
- **Manual refresh now shows a transient loading cue**: clicking Refresh (⌘R)
  briefly sets the menu bar title to "…" and clears the image — across all
  three styles — while the check runs, then re-renders unconditionally so
  the indicator never sticks even when the refresh confirms nothing changed.
  Automatic triggers (timers, wake, path changes) stay indicator-free, per
  the "silent vs manual refresh" field lesson: a spinner on every 30-second
  probe would just be noise.
- **"Checked:" row in the dropdown**, directly under "Since": a manual
  refresh that finds nothing new no longer looks identical to no refresh at
  all. Tracked app-locally (not part of `ExitState`/the JSON output) and
  updated after every fullRefresh/probeTick; reuses the same date/time
  formatter as "Since".

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
