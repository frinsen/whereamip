# Contributing

- Build: `swift build`  ·  Test: `swift test`  ·  App bundle: `scripts/make-app-bundle.sh`
- Logic lives in `WhereAmIPCore` and `WhereAmIPUI`, both unit-tested (see `Tests/`).
- Refresh data snapshots: `scripts/update-flags.sh`, `scripts/update-relay-ranges.sh`.
- PRs run CI (build + test on macOS). Keep the CLI's `--json` output backward compatible.

## E2E VPN suite

The `scripts/e2e/run.sh` test suite drives real VPN transitions (tailscale,
OpenVPN, Warp, Windscribe, native scutil) and asserts that route and DNS
behavior match expectations. Tests run only on opt-in (`WHEREAMIP_E2E=1`) and
require sudo for `networksetup` operations. See `scripts/e2e/secrets/README.md`
for credential setup. **Never run E2E tests in CI** — they're for local
development and calibration only; the gated XCTest target (skipped by default)
captures live detector assertions.
