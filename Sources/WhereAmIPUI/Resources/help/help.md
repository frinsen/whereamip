**The symbol in the menu bar**

- A country **flag** is the country of your real internet exit — where the rest of
  the world sees your traffic coming from. It flips the moment a VPN takes over the
  default route. Settings ▸ Menu Bar Style can show a plain **ISO code** (`DE`) or a
  flag image instead; the ISO code is the readable choice at 16 px.
- The app follows your Mac's language. Settings ▸ Language switches it by hand —
  English or Deutsch — and takes effect the next time you open the menu, no restart.
- A **crossed-out Wi-Fi symbol** means nothing actually loads right now, whatever
  Wi-Fi claims. A **question mark** means the exit could not be placed.
- A small **⚠️ badge** next to the symbol means a confirmed leak — IPv6 or DNS
  traffic is escaping past the tunnel. The dropdown's first rows say which.

**The VPN name**

The tunnel that owns your default route is named from the network service the client
registers with macOS, which works for any VPN, including ones this app has never heard of.
A few clients register nothing at all; those are recognised by fingerprint where that can
be done honestly. When neither works the row reads **VPN (utun4)** — the tunnel is real and
the route is right, only the brand is unknown. ⌘D's report says why, and that is exactly
what an issue needs to get your VPN named.

**Since and Checked**

*Since* is when the state you are looking at began — it only moves when the exit,
route, or connectivity genuinely changes. *Checked* is when that was last verified.
A Refresh that confirms nothing changed moves Checked, not Since. Both are shown to
the second, on purpose: an hours-old state otherwise looks exactly like a fresh one.

**The DNS row**

Opening it shows two different kinds of fact, and confusing them is what makes split
DNS unreadable:

- **Configured resolvers** — what macOS is set to ask, per interface. A local fact,
  always known, no network needed.
- **Queries answered by** — where your queries actually surfaced, measured. Public
  resolvers are load-balanced, so several addresses here are normal. If this list
  sits outside your tunnel while a VPN owns the route, that's a DNS leak.

The measurement is optional: Settings ▸ Check for DNS Leaks turns it off, and then
no query of ours is ever sent. Router-local resolvers that forward to a known
provider are named as such — whether that hop is encrypted is set on the router and
cannot be observed from here.

**Keyboard shortcuts**

- **⌘C** — copy the exit IPv4 address.
- **⌥⌘C** — copy both exit addresses, IPv4 and IPv6. Hold **⌥** with the dropdown
  open and the IP row turns into this wider copy; when no IPv6 exit was measured the
  row says so instead, and nothing is copied.
- **⌘D** — Copy Diagnostics: the whole dropdown as text, with the same warnings it
  is showing you and no others, ready to paste into a bug report. It goes to your
  clipboard and nowhere else.
- **⌘R** — Refresh. **⌘?** — this window. **⌘Q** — quit.

**The welcome window**

The window from your first start is still there, and it has two halves. Settings ▸ Show
Welcome Window reopens the pitch — what the app is, where it lives, and the same three
toggles, showing your current settings. Settings ▸ What's New shows the highlights of the
release that last earned a re-show. Either opens on demand, whatever you have seen before.

**The command line**

Everything the menu bar does, `whereamip` does too:

- `whereamip status` — one glance, as text; `--json` for the full record.
- `whereamip watch` — a new line whenever the exit, route, or connectivity changes.
  `whereamip watch --json >> somefile` is how you keep a history, if you want one.
- `whereamip diagnostics` — the same report ⌘D copies.
- `whereamip debug` — live-streams the diagnostic log while you reproduce a problem.
  Nothing is written to disk, before or after.
- `whereamip config get` / `set` — the same settings the dropdown shows, including
  `config set language de|en|system`.

`whereamip` output stays English on purpose: it is a parseable interface, and bug reports
land in English-language GitHub issues.

**Anything else**

The README answers the longer questions, and bug reports are welcome — attach the
output of `whereamip diagnostics`, or paste what ⌘D copied:
[github.com/frinsen/whereamip](https://github.com/frinsen/whereamip)
