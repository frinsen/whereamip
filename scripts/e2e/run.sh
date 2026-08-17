#!/bin/bash
# WhereAmIP E2E VPN suite — local-only. Mutates real network state; restores on exit.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

[ -n "${CI:-}" ] && e2e_die "refusing to run in CI (mutates host network state)"

E2E_SUDO=0
if sudo -n true 2>/dev/null; then E2E_SUDO=1; else
  e2e_log "no passwordless sudo — backends purevpn-ovpn and dns-swap will be skipped"
  e2e_log "(run 'sudo -v' first, or invoke via: sudo -v && scripts/e2e/run.sh)"
fi
export E2E_SUDO

if [ ! -x "$WHEREAMIP_BIN" ]; then
  e2e_log "building whereamip (release)…"
  (cd "$REPO_ROOT" && swift build -c release >/dev/null)
fi

command -v jq >/dev/null || e2e_die "jq is required (brew install jq)"

e2e_snapshot_state
trap e2e_restore_state EXIT
trap 'e2e_restore_state; trap - EXIT; exit 130' INT TERM

e2e_log "log dir: $E2E_LOG_DIR"

# Baseline sanity check: scenarios (esp. EXPECTS_VPN=0 backends and restore
# assertions) assume the host starts with no VPN up. Warn loudly but proceed —
# refusing to run would block legitimate re-runs after a crash left a VPN
# connected.
e2e_status_json "$E2E_LOG_DIR/pre-baseline.json" || true
if jq -e '.route.isVPN == true' "$E2E_LOG_DIR/pre-baseline.json" >/dev/null 2>&1; then
  baseline_iface="$(jq -r .route.defaultInterface "$E2E_LOG_DIR/pre-baseline.json")"
  e2e_log "!!! BASELINE HAS A VPN UP ($baseline_iface). Scenarios assume a clean baseline — EXPECTS_VPN=0 backends and restore assertions may be skewed. Consider disconnecting all VPNs and re-running."
  echo -e "WARN\tbaseline\tvpn-already-up-$baseline_iface" >> "$E2E_LOG_DIR/scenarios.tsv"
fi

source ./assert.sh

# --- watch stream: verdict state persists only inside one process ------------
WATCH_PID=""; WATCH_OUT=""
watch_start() {
  WATCH_OUT="$E2E_LOG_DIR/$1-watch.jsonl"
  "$WHEREAMIP_BIN" watch --json >> "$WATCH_OUT" 2>/dev/null & WATCH_PID=$!
  e2e_poll_until "watch emitted first state" 30 sh -c "[ -s '$WATCH_OUT' ]"
}
watch_last_json() { tail -1 "$WATCH_OUT"; }
watch_stop() { [ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null || true; WATCH_PID=""; }

route_changed_vs() {  # BASELINE_FILE — has the live route moved off the baseline?
  local now rc=1; now="$(mktemp)"; e2e_status_json "$now" || { rm -f "$now"; return 1; }
  if [ "$(jq -r .route.defaultInterface "$now")" != "$(jq -r .route.defaultInterface "$1")" ] \
    || [ "$(jq -r .route.isVPN "$now")" != "$(jq -r .route.isVPN "$1")" ]; then rc=0; fi
  rm -f "$now"; return $rc
}

_e2e_active_remove() {  # NAME — rebuild E2E_ACTIVE_BACKEND excluding NAME (not a blanket clear;
                         # other backends' tokens left by an earlier failed teardown must survive)
  local _tok _out=""
  for _tok in $E2E_ACTIVE_BACKEND; do
    [ "$_tok" = "$1" ] || _out="$_out${_out:+ }$_tok"
  done
  E2E_ACTIVE_BACKEND="$_out"
}

run_backend_scenario() {  # NAME
  local name="$1" reason
  # Each backend sources fresh in a subshell-free context; unset optionals first.
  unset -f e2e_available e2e_up e2e_down e2e_describe 2>/dev/null || true
  E2E_EXPECTED_VPN_NAME=""; E2E_EXPECTS_VPN=0; E2E_IFACE_PREFIX=""
  source "./backends/$name.sh"
  if ! reason="$(e2e_available)"; then
    e2e_log "SKIP $name: $reason"; echo -e "SKIP\t$name\t$reason" >> "$E2E_LOG_DIR/scenarios.tsv"; return 0
  fi
  e2e_log "=== scenario: $name — $(e2e_describe)"
  local base="$E2E_LOG_DIR/$name-baseline.json"
  if ! e2e_status_json "$base"; then
    e2e_log "FAIL $name: baseline status capture failed"
    echo -e "ERROR\t$name\tbaseline-status-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    return 0
  fi
  if ! watch_start "$name"; then
    echo -e "ERROR\t$name\twatch-start-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    watch_stop
    return 0
  fi

  E2E_ACTIVE_BACKEND="${E2E_ACTIVE_BACKEND:+$E2E_ACTIVE_BACKEND }$name"
  if ! e2e_up; then
    e2e_log "FAIL $name: up failed"; echo -e "ERROR\t$name\tup-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    watch_stop
    if e2e_down 2>/dev/null; then _e2e_active_remove "$name"; fi
    return 0
  fi
  if ! e2e_poll_until "$name route settled" 45 route_changed_vs "$base"; then
    [ "$E2E_EXPECTS_VPN" = 1 ] && { echo -e "ERROR\t$name\tno-route-change" >> "$E2E_LOG_DIR/scenarios.tsv"; }
  fi
  sleep 2   # let the app's escalated full refresh land in the watch stream

  local up="$E2E_LOG_DIR/$name-up.json"
  e2e_status_json "$up" || e2e_log "WARN: $name up-state status capture failed (dependent assertions will FAIL via missing-file jq-guard)"
  if [ "$E2E_EXPECTS_VPN" = 1 ]; then
    a_json_eq "$up" '.route.isVPN' true "$name-route-isvpn"
    [ -n "$E2E_EXPECTED_VPN_NAME" ] && a_json_contains "$up" '.route.vpnName' "$E2E_EXPECTED_VPN_NAME" "$name-vpnname"
  else
    a_json_eq "$up" '.route.isVPN' "$(jq -r .route.isVPN "$base")" "$name-route-unchanged"
  fi
  a_json_in "$up" '.dns.resolvers | length > 0' true "$name-resolvers-nonempty"
  case "$name" in
    tailscale) a_json_contains "$up" '.dns.resolvers[].address' 100.100.100.100 "$name-magicdns";;
    dns-swap)  a_json_contains "$up" '.dns.resolvers[].address' 9.9.9.9 "$name-quad9";;
  esac
  a_record "$up" '.dns.leak' "$name-leak-status-oneshot"
  a_record "$up" '.ipv6Leak' "$name-ipv6leak"
  a_record "$up" '.dns.egressIP' "$name-dns-egress"

  # Confirmation gate (ALWAYS FATAL): the long-lived watch process has seen at
  # most ONE post-transition full refresh right now → .confirmed is impossible
  # unless the gate is broken. One-shot `status` cannot check this (fresh state
  # every run); only the watch stream carries `previous`.
  local wjson; wjson="$(watch_last_json)"
  if [ -n "$wjson" ]; then
    echo "$wjson" > "$E2E_LOG_DIR/$name-watch-after-up.json"
    a_json_in "$E2E_LOG_DIR/$name-watch-after-up.json" '.dns.leak' 'unknown|none|suspected' "$name-CONFIRMATION-GATE"
  else
    _a_result FAIL "$name-CONFIRMATION-GATE" "watch stream empty — gate unverifiable"
  fi

  # Layer 2: real detectors against this live state.
  local expect_vpn="$E2E_EXPECTS_VPN" iface_prefix=""
  [ "$E2E_EXPECTS_VPN" = 1 ] && iface_prefix="${E2E_IFACE_PREFIX:-utun}"
  (cd "$REPO_ROOT" && env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      WHEREAMIP_E2E=1 E2E_EXPECT_VPN="$expect_vpn" E2E_EXPECT_IFACE_PREFIX="$iface_prefix" \
      E2E_BACKEND="$name" E2E_DUMP_DIR="$E2E_LOG_DIR" \
      swift test --filter WhereAmIPE2ETests >> "$E2E_LOG_DIR/$name-xctest.log" 2>&1) \
    && _a_result PASS "$name-layer2" "WhereAmIPE2ETests" \
    || _a_result FAIL "$name-layer2" "see $name-xctest.log"

  if e2e_down; then _e2e_active_remove "$name"; else e2e_log "WARN: $name down failed (restore trap will retry)"; fi
  e2e_poll_until "$name route restored" 45 sh -c \
    "'$WHEREAMIP_BIN' status --json | jq -e '.route.isVPN == $(jq -r .route.isVPN "$base")' >/dev/null" \
    || e2e_log "WARN: $name route not restored within 45s (continuing; restore trap is the backstop)"
  local down="$E2E_LOG_DIR/$name-down.json"
  e2e_status_json "$down" || e2e_log "WARN: $name down-state status capture failed (dependent assertions will FAIL via missing-file jq-guard)"
  a_json_eq "$down" '.route.isVPN' "$(jq -r .route.isVPN "$base")" "$name-restored"
  watch_stop
  echo -e "DONE\t$name" >> "$E2E_LOG_DIR/scenarios.tsv"
}

# BACKENDS is overridable via E2E_ONLY so non-interactive runs (CI-adjacent
# dry validation, the Task 9 acceptance run) can exclude prompt-mode backends
# (purevpn-scutil waits on a manual app click) or restrict the run to a
# specific subset without touching live VPN state.
BACKENDS="${E2E_ONLY:-tailscale purevpn-scutil purevpn-ikev dns-swap warp windscribe windscribe-wg purevpn-ovpn}"
for b in $BACKENDS; do run_backend_scenario "$b"; done

# --- cross-backend: resolver change UNDER a VPN → escalation → 2nd full
# refresh → the two-refresh gate progression becomes observable in ONE watch.
run_cross_dnsswap_under_vpn() {
  local vpn=tailscale
  local vpn_up=0 dns_up=0
  source "./backends/$vpn.sh";      e2e_available >/dev/null || { e2e_log "SKIP cross (no $vpn)"; return 0; }
  source "./backends/dns-swap.sh";  e2e_available >/dev/null || { e2e_log "SKIP cross (no sudo)"; return 0; }
  e2e_log "=== cross-scenario: dns-swap under $vpn"
  local base="$E2E_LOG_DIR/cross-baseline.json"
  if ! e2e_status_json "$base"; then
    e2e_log "FAIL cross: baseline status capture failed"
    echo -e "ERROR\tcross-dnsswap-under-vpn\tbaseline-status-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    return 0
  fi

  # Unconditional cleanup path — called from every exit route below so a
  # failure partway through never leaves the VPN, resolver swap, or watch
  # process stuck. Tears down (via E2E_ACTIVE_BACKEND, which may include a
  # backend whose e2e_up failed but could have partially connected) in
  # reverse bring-up order, re-sourcing each named backend immediately before
  # calling ITS e2e_down since sourcing the next backend overwrites functions.
  cross_teardown() {
    local _cross_reversed="" _b
    for _b in $E2E_ACTIVE_BACKEND; do _cross_reversed="$_b $_cross_reversed"; done
    for _b in $_cross_reversed; do
      source "./backends/$_b.sh"
      if e2e_down; then
        [ "$_b" = "dns-swap" ] && dns_up=0
        [ "$_b" = "$vpn" ] && vpn_up=0
        E2E_ACTIVE_BACKEND="${E2E_ACTIVE_BACKEND% $_b}"
        [ "$E2E_ACTIVE_BACKEND" = "$_b" ] && E2E_ACTIVE_BACKEND=""
      else
        e2e_log "WARN: cross $_b down failed (restore trap will retry)"
      fi
    done
    watch_stop
  }

  if ! watch_start cross; then
    echo -e "ERROR\tcross-dnsswap-under-vpn\twatch-start-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    watch_stop
    return 0
  fi

  source "./backends/$vpn.sh"
  E2E_ACTIVE_BACKEND="${E2E_ACTIVE_BACKEND:+$E2E_ACTIVE_BACKEND }$vpn"
  if ! e2e_up; then
    e2e_log "FAIL cross: $vpn up failed"
    echo -e "ERROR\tcross-dnsswap-under-vpn\t$vpn-up-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    cross_teardown; return 0
  fi
  vpn_up=1
  e2e_poll_until "cross: vpn up" 45 route_changed_vs "$base" \
    || e2e_log "WARN: cross $vpn route did not settle within timeout"
  sleep 2

  source "./backends/dns-swap.sh"
  E2E_ACTIVE_BACKEND="$vpn dns-swap"
  if ! e2e_up; then          # resolver change → escalation
    e2e_log "FAIL cross: dns-swap up failed"
    echo -e "ERROR\tcross-dnsswap-under-vpn\tdns-swap-up-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    cross_teardown; return 0
  fi
  dns_up=1
  # Bounded poll (was a fixed sleep 5) for the escalated full refresh #2 to land
  # in the watch stream, carrying the new 9.9.9.9 resolver.
  _cross_resolver_seen() { watch_last_json | jq -e '.dns.resolvers[].address | select(. == "9.9.9.9")' >/dev/null 2>&1; }
  e2e_poll_until "cross: resolver escalation seen (9.9.9.9)" 30 _cross_resolver_seen \
    || e2e_log "WARN: cross resolver escalation not observed within 30s poll — proceeding to assertion (will FAIL with evidence)"
  local w="$E2E_LOG_DIR/cross-after-swap.json"; watch_last_json > "$w"
  a_json_contains "$w" '.dns.resolvers[].address' 9.9.9.9 "cross-resolver-escalation-seen"
  a_record "$w" '.dns.leak' "cross-leak-after-2-full-refreshes"

  cross_teardown
  echo -e "DONE\tcross-dnsswap-under-vpn" >> "$E2E_LOG_DIR/scenarios.tsv"
}
run_cross_dnsswap_under_vpn

{
  echo "# E2E run $(basename "$E2E_LOG_DIR")"
  echo; echo "## Scenarios"; column -t -s$'\t' "$E2E_LOG_DIR/scenarios.tsv" 2>/dev/null || true
  echo; echo "## Assertions"; column -t -s$'\t' "$E2E_LOG_DIR/assertions.tsv" 2>/dev/null || true
  echo; echo "## Calibration data (recorded, not judged)"
  column -t -s$'\t' "$E2E_LOG_DIR/calibration.tsv" 2>/dev/null || true
} > "$E2E_LOG_DIR/summary.md"
e2e_log "summary: $E2E_LOG_DIR/summary.md"
[ "${E2E_FAILED:-0}" = 1 ] && { e2e_log "RESULT: FAILURES (see summary)"; exit 1; }
e2e_log "RESULT: all assertions passed"
