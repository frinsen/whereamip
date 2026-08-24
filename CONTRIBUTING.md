# Contributing

- Build: `swift build`  ·  Test: `swift test`  ·  App bundle: `scripts/make-app-bundle.sh`
- Logic lives in `WhereAmIPCore` and `WhereAmIPUI`, both unit-tested (see `Tests/`).
- Refresh data snapshots: `scripts/update-flags.sh`, `scripts/update-relay-ranges.sh`.
- PRs run CI (build + test on macOS). Keep the CLI's `--json` output backward compatible.

## Editing user-facing texts

No Swift needed for any of these:

- **A menu/settings/notification label, or the welcome window's chrome**: edit the
  value in `Sources/WhereAmIPUI/Resources/en.lproj/Localizable.strings`. Keep the
  key and its `%@`/`%d` placeholders (count and order); everything else is free.
- **The first-start onboarding text**:
  `Sources/WhereAmIPUI/Resources/welcome/intro.md`.
- **The help window's body** (⌘? in the dropdown):
  `Sources/WhereAmIPUI/Resources/help/help.md` — one evergreen document, edited in
  place. Section titles are `**bold paragraphs**`, not `#` headings: the renderer
  strips hashes without styling what's left. `HelpContentTests` asserts the topics
  it must still cover, so dropping a section is caught.
- **A new release's what's-new highlights**: add
  `Sources/WhereAmIPUI/Resources/welcome/<milestone>.md` (3–5 user-facing bullets)
  and bump `welcomeMilestone` in `Sources/WhereAmIPCore/Version.swift` to match.
  Bumping without adding the file fails `WelcomeContentTests`, so an upgrade can't
  silently re-show the first-run pitch.

Adding a *new* string does need Swift: a case in `L10nKey` (`Sources/WhereAmIPUI/L10n.swift`),
the matching line in the .strings file, and `L10n.string(.thatKey)` at the call
site. `whereamip` CLI output is not localized — it's a parseable API.

## E2E VPN suite

The `scripts/e2e/run.sh` test suite drives real VPN transitions (tailscale,
OpenVPN, Warp, Windscribe, native scutil) and asserts that route and DNS
behavior match expectations. Running `scripts/e2e/run.sh` is itself the
opt-in step — it sets `WHEREAMIP_E2E=1` for you before invoking the gated
XCTest target (`WhereAmIPE2ETests`, skipped by default otherwise), so you
don't need to set that variable yourself. Sudo is only needed for the
`dns-swap` and `purevpn-ovpn` backends (`networksetup`/`openvpn`
operations); without passwordless sudo those two backends are skipped and
the rest of the suite still runs. See `scripts/e2e/secrets/README.md` for
credential setup. **Never run E2E tests in CI** — they're for local
development and calibration only; the gated XCTest target (skipped by default)
captures live detector assertions.

## Adding a VPN fingerprint

Most VPNs need no code: if the client registers a macOS network service, `SCServiceNamer`
finds its name and the app shows it. That path is structural and vendor-neutral — prefer
fixing it there if a service name exists but isn't being read.

A *fingerprint* is for the clients that register nothing (classic daemons, some native
profiles). They live in `Sources/WhereAmIPCore/VPNNamer.swift`:

- `bundleIDNames` — the app-presence table. Adding a row is the cheapest contribution and
  needs only the bundle id and a display name. It is a LAST resort in the ladder, and it
  deliberately declines to guess when two known VPN apps are running at once.
- The address/process tells in `name(...)` — stronger, and held to a higher bar.

The bar for a new tell, in one rule: **structural evidence generalises, fingerprints
don't.** So a fingerprint must either be vendor-specific by construction (a constant that
vendor's own client assigns, like WARP's `172.16.0.2`) or be corroborated by that vendor's
own presence (a bundle id or a visible process, like the CGNAT tell requiring Tailscale
evidence — `100.64/10` is public RFC 6598 space that any mesh VPN may use, so the address
alone proves nothing). And when a tell doesn't fire it must fail **downward** — to the next
piece of evidence, or to the generic "VPN (utunN)" label — never sideways into some other
vendor's brand name. A wrong name shown confidently is worse than no name.

Two traps, both already paid for (see the doc comments):

- `ProcessScanner` cannot see processes owned by other users, so **root daemons are
  invisible**. A check for one is dead code that silently never fires. Match the user-owned
  GUI processes the app also runs.
- `proc_name` returns truncated short names ("OpenVPN Connect Helper (Rendere"). Match by
  prefix, never against a full executable name.

Tests expected with a fingerprint PR (`Tests/WhereAmIPCoreTests/VPNNamerTests.swift`):
the positive case; the uncorroborated/negative case proving it does NOT fire; proof that it
doesn't capture a tunnel another tell already identifies; and the diagnosis case if
relevant. If you can't test it, say so in the PR — a real `whereamip diagnostics` paste
from the affected machine is good evidence.

## Adding a translation

Two halves, and only one of them is automatic.

**The strings** are automatic: copy `Sources/WhereAmIPUI/Resources/en.lproj/Localizable.strings`
to `<code>.lproj/Localizable.strings`, translate the values, and macOS picks the file when
the system language matches. No Swift, no call-site change.

- Keys stay untouched — a key is a code identifier, not text.
- `%@` / `%d` keep their **count and order** from the English value. `String(format:)` fills
  them positionally, so a dropped placeholder is a crash that only speakers of that language
  would ever hit; `L10nTests.testPlaceholdersMatchTheBaseLocaleExactly` enforces it.
- Use the platform's own vocabulary rather than a literal translation — what German macOS
  calls "Mitteilungen", not "Benachrichtigungen". Check System Settings, not a dictionary.
- Sibling grammar applies **per locale**: the labels must be parallel to each other in the
  target language, not to the English source.
- Watch fixed-width labels. `welcome.notify.caption` is a single-line slot that truncates
  rather than wraps; `L10nTests.testNotifyCaptionFitsItsSingleLineSlotInEveryLocale`
  measures it in every locale for exactly that reason.

**The bundled Markdown** is not automatic: `welcome/` and `help/` are `.copy`'d resources,
not localized ones. Put a translation in a language subfolder beside the English file —
`welcome/de/intro.md`, `welcome/de/<milestone>.md`, `help/de/help.md` — and
`LocalizedMarkdown` will prefer it. Fallback is **per file**, so a partial translation is
fine: any file you haven't translated is served in English rather than dropping the whole
locale.

Then:

- add the language code to `L10nTests.shippedLocales` — that is what subjects it to the
  completeness and placeholder checks;
- add it to `CFBundleLocalizations` in `scripts/make-app-bundle.sh`, or macOS treats the app
  as English-only (the strings live in a nested SPM bundle, so it cannot infer them);
- run `plutil -lint` on your `.strings` file. German quotation marks are a trap: the closing
  „…“ must be U+201C, and a straight `"` inside a value silently ends the string early.

Not translated, deliberately: `whereamip` output, the JSON, `whereamip diagnostics` / the ⌘D
report, and log messages. Those are a parseable interface, and reports written in them land
in English-language issues — the UI speaks the user's language, the diagnostics speak the
project's.
