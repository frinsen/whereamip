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
# Backends + scenarios appended by later tasks.

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
  local now; now="$(mktemp)"; e2e_status_json "$now"
  [ "$(jq -r .route.defaultInterface "$now")" != "$(jq -r .route.defaultInterface "$1")" ] \
    || [ "$(jq -r .route.isVPN "$now")" != "$(jq -r .route.isVPN "$1")" ]
}

run_backend_scenario() {  # NAME
  local name="$1" reason
  # Each backend sources fresh in a subshell-free context; unset optionals first.
  unset -f e2e_available e2e_up e2e_down e2e_describe 2>/dev/null || true
  E2E_EXPECTED_VPN_NAME=""; E2E_EXPECTS_VPN=0
  source "./backends/$name.sh"
  if ! reason="$(e2e_available)"; then
    e2e_log "SKIP $name: $reason"; echo -e "SKIP\t$name\t$reason" >> "$E2E_LOG_DIR/scenarios.tsv"; return 0
  fi
  e2e_log "=== scenario: $name — $(e2e_describe)"
  local base="$E2E_LOG_DIR/$name-baseline.json"; e2e_status_json "$base"
  watch_start "$name"

  if ! e2e_up; then
    e2e_log "FAIL $name: up failed"; echo -e "ERROR\t$name\tup-failed" >> "$E2E_LOG_DIR/scenarios.tsv"
    watch_stop; e2e_down 2>/dev/null || true; return 0
  fi
  if ! e2e_poll_until "$name route settled" 45 route_changed_vs "$base"; then
    [ "$E2E_EXPECTS_VPN" = 1 ] && { echo -e "ERROR\t$name\tno-route-change" >> "$E2E_LOG_DIR/scenarios.tsv"; }
  fi
  sleep 2   # let the app's escalated full refresh land in the watch stream

  local up="$E2E_LOG_DIR/$name-up.json"; e2e_status_json "$up"
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
  fi

  e2e_down || e2e_log "WARN: $name down failed (restore trap will retry)"
  e2e_poll_until "$name route restored" 45 sh -c \
    "'$WHEREAMIP_BIN' status --json | jq -e '.route.isVPN == $(jq -r .route.isVPN "$base")' >/dev/null"
  local down="$E2E_LOG_DIR/$name-down.json"; e2e_status_json "$down"
  a_json_eq "$down" '.route.isVPN' "$(jq -r .route.isVPN "$base")" "$name-restored"
  watch_stop
  echo -e "DONE\t$name" >> "$E2E_LOG_DIR/scenarios.tsv"
}

# BACKENDS is overridable via E2E_ONLY so non-interactive runs (CI-adjacent
# dry validation, the Task 9 acceptance run) can exclude prompt-mode backends
# (purevpn-scutil waits on a manual app click) or restrict the run to a
# specific subset without touching live VPN state.
BACKENDS="${E2E_ONLY:-tailscale purevpn-scutil dns-swap warp windscribe purevpn-ovpn}"
for b in $BACKENDS; do run_backend_scenario "$b"; done
