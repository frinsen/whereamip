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
