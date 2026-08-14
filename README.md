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
- Three menu bar styles: emoji flag (🇩🇪), ISO country code (`DE`), or crisp flag image — pick per taste in Settings; ISO code is the monochrome, accessibility-friendly option (🇳🇱 vs 🇱🇺 at 16 px is hard, `NL` vs `LU` isn't)
- Full functionality via CLI (`whereamip status --json`)
- Notifications on exit/connectivity change (off by default), launch at login
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

Then enable **Settings ▸ Launch at Login** inside the app so it starts automatically next time.

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

$ whereamip config get       # notify=false / style=emoji
$ whereamip config set style code
$ whereamip config set notify true
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

## Privacy — your data stays yours

WhereAmIP has **no tracking, no analytics, no history, and no logs**. Nothing is written to disk except your display-style preference. The only network requests are the documented lookups needed to answer "where do I exit right now" (keyless public geo APIs, a connectivity probe, and the Private Relay check) — your IP is never sent anywhere else, and past states are gone the moment they change. If you *want* a history, you opt in yourself: `whereamip watch --json >> your-own-file` keeps it wherever you decide.

## Roadmap

- **IPv6 leak detector** (priority): probe IPv4 and IPv6 exits separately; when the route says VPN but one stack exits natively, show ⚠️ "IPv6 leak — v6 traffic exits via your ISP". Found in the wild: PureVPN profiles that tunnel only IPv4 while native IPv6 keeps leaking.
- Faster far-end detection: a VPN server switch inside the same tunnel produces no local route event, so today the geo backstop (5 min) is the only trigger.
- IPv6 route awareness: v6 default-route inspection and the v6 hijack pair (`::/1` + `8000::/1`); re-add IPv6 relay egress ranges.
- Optional history: `whereamip watch --json >> file` already works as a manual log; consider last-N transitions in the dropdown.

## Credits

Flag images by [Flagpedia.net](https://flagpedia.net) (public domain).

## License

MIT
