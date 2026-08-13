# Contributing

- Build: `swift build`  ·  Test: `swift test`  ·  App bundle: `scripts/make-app-bundle.sh`
- Logic lives in `WhereAmIPCore` and `WhereAmIPUI`, both unit-tested (see `Tests/`).
- Refresh data snapshots: `scripts/update-flags.sh`, `scripts/update-relay-ranges.sh`.
- PRs run CI (build + test on macOS). Keep the CLI's `--json` output backward compatible.
