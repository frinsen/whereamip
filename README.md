<p align="center">
  <img src="docs/icon-source.svg" width="140" alt="WhereAmIP icon — a mesh flag with a location pin and network route lines">
</p>

# WhereAmIP

> Where am I(P)? — a native macOS menu bar app that shows the country flag of your current internet exit point, tells you when your connection is *actually* dead, and untangles what your VPNs and iCloud Private Relay are really doing to your traffic.

Stylized as **WhereAmIP** in the UI; the process, repo, and Homebrew formula name are lowercase `whereamip`.

<!-- TODO: take a real screenshot of the menu open (⌘⇧4) and drop it into docs/screenshot.png, then uncomment: -->
<!-- ![WhereAmIP menu bar dropdown](docs/screenshot.png) -->

## Features

- 🇩🇪 Country flag of your exit IP in the menu bar — flips to 🇳🇱 the moment a VPN grabs your default route, ❌ when the internet is unreachable (even when Wi-Fi claims otherwise)
- Real-reachability probe, not interface status — catches the "connected but blackholed" state
- Dropdown: public IP (click to copy), city/country, ISP/org, which VPN interface owns the default route, last-change timestamp
- iCloud Private Relay awareness — knows Safari may exit somewhere your apps don't
- Dual-stack IPv6 leak detection — probes your IPv4 and IPv6 exits independently (stack-pinned lookups, not a single dual-stack host); when a VPN owns the v4 route but IPv6 still exits natively and the two genuinely differ, a confirmed ⚠️ IPv6 leak warning shows up everywhere (menu bar badge, dropdown row, notification, CLI). Found in the field: PureVPN profiles that tunnel only IPv4 while native IPv6 keeps leaking via the home ISP
- DNS resolver display and leak detection — shows which resolvers macOS uses (per interface) and whether encrypted DNS (DoH/DoT profile) is in force; an optional active probe (a lightweight TXT lookup of a Google-operated beacon, `o-o.myaddr.l.google.com`, sent via mDNSResponder on each full refresh) checks that queries exit through the VPN tunnel; `config set dns false` disables the probe entirely, so no such query is ever sent
- Three menu bar styles: emoji flag (🇩🇪), ISO country code (`DE`), or crisp flag image — pick per taste in Settings; ISO code is the monochrome, accessibility-friendly option (🇳🇱 vs 🇱🇺 at 16 px is hard, `NL` vs `LU` isn't)
- Full functionality via CLI (`whereamip status --json`)
- Notifications (off by default) — alerts on exit, route, or connectivity changes; launch at login
- Quiet update hint — checks the latest GitHub release daily and whenever you hit Refresh; when one's out, a single dropdown row lets you copy `brew upgrade whereamip`. Once brew has installed it, the row becomes "↻ Restart to finish update" — one click relaunches into the new version. No popups, no badges, respects your Settings, and the app itself never downloads or self-updates — brew does
- One-time welcome window on first start (and once after major releases): what the app is, where it lives, and live toggles for Launch at Login, Add to Applications folder, and Show Notifications — no permission prompts unless you flip a toggle. Reopen it anytime via Settings
- Honest freshness: the dropdown shows both "Since" (when the current state began, to the second) and "Checked" (when it was last verified), and a manual Refresh shows a brief loading cue in the menu bar
- Native AppKit (`NSStatusItem` + `NSMenu`), zero third-party runtime dependencies, no API keys

## Install

Installation uses [Homebrew](https://brew.sh), the standard package manager for macOS — if you don't have it yet, it's a one-line install from [brew.sh](https://brew.sh).

```bash
brew tap frinsen/tap
brew trust frinsen/tap   # newer Homebrew requires explicitly trusting third-party taps
brew install whereamip
```

This is a build-from-source formula (Xcode command line tools required) — no Gatekeeper dance, no unsigned-binary warnings.

### Start the app

```bash
open "$(brew --prefix)/opt/whereamip/libexec/WhereAmIP.app"
```

Then enable **Settings ▸ Launch at Login** inside the app so it starts automatically next time. A first-start window also walks you through this — it offers Launch at Login and Add to Applications folder as live toggles the moment the app opens for the first time.

Optional — make it show up in /Applications (the symlink survives upgrades); the first-start window's "Add to Applications folder" toggle (or **Settings ▸ Add to Applications folder** any time after) does this for you, but the manual `ln -s` below still works too for CLI-only folks:

```bash
ln -s "$(brew --prefix)/opt/whereamip/libexec/WhereAmIP.app" /Applications/WhereAmIP.app
```

> If Launch at Login stops working after a `brew upgrade`, re-toggle it in Settings.

## CLI

```bash
$ whereamip status
🇩🇪 203.0.113.7  Berlin, DE
   Deutsche Telekom AG
route: en0

$ whereamip status --json
{"connectivity":"online","exit":{"city":"Berlin","countryCode":"DE","ip":"203.0.113.7",...

$ whereamip watch            # prints a new status line whenever exit IP, route, or connectivity changes
$ whereamip watch --json

$ whereamip config get       # notify=false / style=emoji / updates=true / dns=true
$ whereamip config set style code
$ whereamip config set notify true
$ whereamip config set updates false
$ whereamip config set dns false
```

## FAQ

**Is my VPN actually working?**
Look at the flag. WhereAmIP shows the country of your real exit IP in the macOS menu bar — the moment a VPN (Tailscale, OpenVPN, PureVPN, WireGuard, …) takes over your default route, the flag flips. The dropdown names the VPN that owns the route, based on the routing table, not on which apps happen to be running.

**How do I show my public IP in the menu bar on a Mac?**
`brew install` WhereAmIP, and your current public IP is one click away — with city, country, and ISP. Click the IP to copy it.

**Am I connected to the internet right now?**
WhereAmIP probes real reachability instead of trusting Wi-Fi status. If the network looks up but nothing actually loads (a classic stale-VPN symptom), the flag becomes an offline symbol — and if OpenVPN's leftover hijack routes are the cause, the dropdown says so.

**Why does Safari show a different location than my other apps?**
That's iCloud Private Relay: it carries Safari traffic through Apple's relay while other apps take the system route. WhereAmIP detects this split and shows both exits.

**Does it phone home?**
No — see Privacy below. No accounts, no API keys, no tracking.

**How do I debug it / attach logs to a bug report?**
Run `whereamip debug`, reproduce the issue, and paste the output into your bug report. It live-streams WhereAmIP's diagnostic log — nothing is written to disk, before or after you run it.

## Privacy — your data stays yours

WhereAmIP has **no tracking, no analytics, no history, and no log files**. Nothing is written to disk except your display-style preference. The only network requests are the documented lookups needed to answer "where do I exit right now" (keyless public geo APIs, a connectivity probe, the Private Relay check, and — for the dual-stack IPv6 leak detector — stack-pinned lookups to `api4.ipify.org`/`api6.ipify.org` over HTTPS) — your IP is never sent anywhere else, and past states are gone the moment they change. If you *want* a history, you opt in yourself: `whereamip watch --json >> your-own-file` keeps it wherever you decide.

WhereAmIP also checks `api.github.com/repos/frinsen/whereamip/releases/latest` once a day (and whenever you hit Refresh) to see if a newer release exists — this is a passive version check only, it never downloads or installs anything, it just shows a dropdown row that copies `brew upgrade whereamip` for you to run yourself. This check is on by default; turn it off with `whereamip config set updates false` (or the "Check for Updates" toggle in Settings) and no such request is ever made.

WhereAmIP does emit diagnostics through Apple's unified logging (`os.Logger`), but this creates no privacy problem: the app never writes a log file anywhere. Entries are logged at debug level, which macOS does not persist to disk by default — they exist only in the local system's in-memory ring buffer while you're actively streaming them with `whereamip debug` (or Console.app), and expire on their own shortly after. Nothing is collected, stored, or sent off your Mac.

## Roadmap

- **IPv6 hijack detection** (Phase 2 of the IPv6 leak detector): the v6 hijack pair (`::/1` + `8000::/1`), analogous to the existing OpenVPN IPv4 hijack detection; re-add IPv6 relay egress ranges.
- Faster far-end detection: a VPN server switch inside the same tunnel produces no local route event, so today the geo backstop (5 min) is the only trigger.
- Optional history: `whereamip watch --json >> file` already works as a manual log; consider last-N transitions in the dropdown.
- **Texts out of code + multi-language**: move all user-facing strings into localization catalogs and long-form content (onboarding, per-release what's-new highlights) into bundled Markdown files — centrally editable, translation-ready (`de` first). The what's-new window then renders real release highlights instead of repeating the pitch.
- Signed & notarized downloads (needs an Apple Developer membership): would turn the unsigned release zip into a double-click install, enable a fast `brew install --cask` path, and drop the Gatekeeper caveats. Deliberately deferred until the project earns it — the build-from-source formula already installs cleanly without Apple's toll.
- Flag-image style polish: rounded corners + hairline border so the PNG flags hold up on any menu bar background (emoji and ISO styles are unaffected).
- Separate bundle id for dev builds (`….dev`): test bundles currently share settings and notification permissions with the installed app — convenient, but experiments can touch real state.

## Credits

Flag images by [Flagpedia.net](https://flagpedia.net) (public domain).

## License

MIT
