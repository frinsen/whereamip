# PureVPN scutil spike — verdict

**Verdict: `refused`** (stop worked, start did not; NE app did not auto-reconnect within the 60s+ poll window)

`scutil --nc start "PureVPN"` cannot be relied on to drive the PureVPN NetworkExtension app profile from the CLI. `stop` does work. `start` transitions to `Connecting` and then silently falls back to `Disconnected` without ever reaching `Connected`.

## Environment

- Precondition: PureVPN was `Connected` before this spike started.
- `whereamip` release binary not present (`.build/release/whereamip` missing) — view step skipped.

## Step 1: Record initial state

```
$ scutil --nc status "PureVPN" | head -1
Connected
```
Timestamp: 2026-08-16T21:12:26Z

```
$ .build/release/whereamip status 2>/dev/null | head -3
(no output — binary not built, step skipped)
```

## Step 2: Try stop

```
$ scutil --nc stop "PureVPN"
```
Run at: 2026-08-16T21:12:35Z

```
$ sleep 3; scutil --nc status "PureVPN" | head -1
Connecting
```
Checked at: 2026-08-16T21:12:38Z (transitional — NE state machine had not settled yet)

```
$ scutil --nc status "PureVPN" | head -1
Disconnected
```
Checked at: 2026-08-16T21:13:53Z

**Result: `stop` works** — PureVPN settled to `Disconnected` a few seconds after the transitional `Connecting` state.

## Step 3: Try start

```
$ scutil --nc start "PureVPN"
```
Run at: 2026-08-16T21:13:57Z

```
$ sleep 5; scutil --nc status "PureVPN" | head -1
Connecting
```
Checked at: 2026-08-16T21:14:02Z

```
$ scutil --nc status "PureVPN" | head -1
Connecting
```
Checked at: 2026-08-16T21:14:11Z

```
$ scutil --nc status "PureVPN" | head -1
Disconnected
```
Checked at: 2026-08-16T21:14:21Z

**Result: `start` fails** — status moved `Connecting` → `Connecting` → `Disconnected`. The NE app never reached `Connected`. No error was printed to stdout/stderr by `scutil`; the failure is silent (only observable via polling status).

## Step 4: Ensure restored — poll for auto-reconnect (up to 60s+)

Per the stop-only/refused branch of the spike procedure, polled `scutil --nc status "PureVPN"` every ~5-10s (actual cadence stretched by tool round-trip latency) after the confirmed start failure at 2026-08-16T21:14:21Z:

| Timestamp (UTC) | Status |
|---|---|
| 2026-08-16T21:14:55Z | Disconnected |
| 2026-08-16T21:15:04Z | Disconnected |
| 2026-08-16T21:15:12Z | Disconnected |
| 2026-08-16T21:15:23Z | Disconnected |
| 2026-08-16T21:15:33Z | Disconnected |

Elapsed from confirmed start failure to end of poll window: ~72s. No auto-reconnect occurred. Per the spike procedure, no further CLI mutating commands were attempted (no other network-mutating commands were run, per constraint).

**Final PureVPN state at end of task: `Disconnected`.**

**ACTION NEEDED: PureVPN is disconnected — reconnect via the PureVPN app.**

## Conclusion for Task 4

`purevpn-scutil.sh` must encode capability mode `refused` for this environment/app-version combination: `scutil --nc stop` is usable to force-disconnect for E2E setup, but `scutil --nc start` cannot be trusted to bring PureVPN back up — the harness must not depend on CLI `start` to restore connectivity, and any E2E flow that needs PureVPN reconnected must prompt the operator to do so manually via the app.
