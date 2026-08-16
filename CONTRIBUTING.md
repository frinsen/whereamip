# Contributing

- Build: `swift build`  ·  Test: `swift test`  ·  App bundle: `scripts/make-app-bundle.sh`
- Logic lives in `WhereAmIPCore` and `WhereAmIPUI`, both unit-tested (see `Tests/`).
- Refresh data snapshots: `scripts/update-flags.sh`, `scripts/update-relay-ranges.sh`.
- PRs run CI (build + test on macOS). Keep the CLI's `--json` output backward compatible.

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
