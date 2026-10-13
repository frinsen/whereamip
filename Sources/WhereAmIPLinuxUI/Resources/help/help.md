**The icon in the panel**

- A country **flag** is the country of your real internet exit — where the rest of
  the world sees your traffic coming from. It flips the moment a VPN takes over the
  default route. Settings ▸ Menu Bar Style can show the **ISO code** (`DE`) on a badge or
  the emoji flag instead; the ISO code is the readable choice at panel size.
- The app follows your desktop's language. Settings ▸ Language switches it by hand —
  English or Deutsch — and takes effect the next time you open the menu, no restart.
- A **crossed-out network icon** means nothing actually loads right now, whatever
  Wi-Fi or Ethernet claims. A **question mark** means the exit could not be placed.
- A small **warning triangle** in the icon's corner means a confirmed leak — IPv6 or DNS
  traffic is escaping past the tunnel. The menu's first rows say which.

**The VPN name**

The tunnel that owns your default route is named from the connection NetworkManager runs
it as — whatever you called it in the network settings — which works for any VPN set up
there. Clients that bypass NetworkManager are recognised by the interface name their own
client assigns (Tailscale, Cloudflare WARP, NordVPN, Mullvad) or, for OpenVPN, by its
process. When none of that works the row reads **VPN (tun0)** — the tunnel is real and the
route is right, only the brand is unknown. Copy Diagnostics says why, and that is exactly
what an issue needs to get your VPN named.

**Since and Checked**

*Since* is when the state you are looking at began — it only moves when the exit,
route, or connectivity genuinely changes. *Checked* is when that was last verified.
A Refresh that confirms nothing changed moves Checked, not Since. Both are shown to
the second, on purpose: an hours-old state otherwise looks exactly like a fresh one.

**The DNS row**

Opening it shows two different kinds of fact, and confusing them is what makes split
DNS unreadable:

- **Configured resolvers** — what this machine is set to ask, per interface, as
  systemd-resolved reports it. A local fact, always known, no network needed.
- **Queries answered by** — where your queries actually surfaced, measured. Public
  resolvers are load-balanced, so several addresses here are normal. If this list
  sits outside your tunnel while a VPN owns the route, that's a DNS leak.

The measurement is optional: Settings ▸ Check for DNS Leaks turns it off, and then
no query of ours is ever sent. Router-local resolvers that forward to a known
provider are named as such — whether that hop is encrypted is set on the router and
cannot be observed from here.

**Copying**

- Click the **exit IP** row to copy the address. With an IPv6 exit, **Copy both exit
  addresses** copies IPv4 and IPv6, one per line.
- **Copy Diagnostics** copies the whole menu as text, with the same warnings it is showing
  you and no others, ready to paste into a bug report. It goes to your clipboard and
  nowhere else.
- The DNS row's submenu copies its resolver lists, bare addresses one per line.

**No icon in the panel?**

Panels show app icons through the StatusNotifierItem (AppIndicator) standard. Most do out
of the box; elementary OS's panel needs the community **AppIconTray** indicator first. If
no panel can show the icon, WhereAmIP says so once, in a notification — and the command line
below keeps working either way.

**The welcome window**

Settings ▸ Show Welcome Window reopens the window from your first start — what the app is,
and the same three toggles, showing your current settings.

**The command line**

Everything the panel does, `whereamip` does too:

- `whereamip status` — one glance, as text; `--json` for the full record.
- `whereamip watch` — a new line whenever the exit, route, or connectivity changes.
  `whereamip watch --json >> somefile` is how you keep a history, if you want one.
- `whereamip diagnostics` — the same report Copy Diagnostics copies.
- `whereamip debug` — runs a live trace of every check while you reproduce a problem.
  Nothing is written to disk, before or after. To trace the panel app itself, start it
  with `WHEREAMIP_DEBUG=1 whereamip-indicator`.
- `whereamip config get` / `set` — the same settings the menu shows, including
  `config set language de|en|system`.

`whereamip` output stays English on purpose: it is a parseable interface, and bug reports
land in English-language GitHub issues.

**Anything else**

The README answers the longer questions, and bug reports are welcome — attach the
output of `whereamip diagnostics`, or paste what Copy Diagnostics copied:
[github.com/frinsen/whereamip](https://github.com/frinsen/whereamip)
