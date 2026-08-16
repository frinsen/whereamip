#!/bin/bash
# Shared plumbing for the E2E VPN suite. Sourced by run.sh and backends.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$E2E_ROOT/../.." && pwd)"
E2E_LOG_DIR="${E2E_LOG_DIR:-$E2E_ROOT/logs/$(date -u +%Y%m%dT%H%M%SZ)}"
WHEREAMIP_BIN="$REPO_ROOT/.build/release/whereamip"
export E2E_LOG_DIR WHEREAMIP_BIN
mkdir -p "$E2E_LOG_DIR"

e2e_log() { printf '[e2e %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$E2E_LOG_DIR/run.log"; }
e2e_die() { e2e_log "FATAL: $*"; exit 1; }

# --- initial-state snapshot & guaranteed restore -----------------------------
# Captures what we may mutate: PureVPN/Tailscale connection state, DNS servers
# of the primary service. Restore is idempotent and safe to call repeatedly.
E2E_SNAP_DIR="$E2E_LOG_DIR/snapshot"

# Space-separated list of backend names currently "up" (in bring-up order).
# run.sh sets this immediately before e2e_up and clears/trims it immediately
# after the matching successful e2e_down, so that if the process dies (or a
# bare call trips set -e) mid-scenario, e2e_restore_state below knows exactly
# which backend(s) are still live and how to tear them down.
E2E_ACTIVE_BACKEND=""

e2e_snapshot_state() {
  mkdir -p "$E2E_SNAP_DIR"
  scutil --nc status "PureVPN" 2>/dev/null | head -1 > "$E2E_SNAP_DIR/purevpn.state" || true
  /Applications/Tailscale.app/Contents/MacOS/Tailscale status --peers=false \
    > "$E2E_SNAP_DIR/tailscale.state" 2>&1 || true
  # Detect active network service from default route interface.
  local iface; iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  local svc
  if [ -n "$iface" ]; then
    svc="$(networksetup -listallhardwareports | awk -v dev="$iface" '/^Hardware Port:/{port=substr($0,16)} /^Device:/{if ($2==dev) print port}')"
  fi
  if [ -z "${svc:-}" ]; then
    e2e_log "warning: active interface detection failed, falling back to service list heuristic"
    svc="$(networksetup -listallnetworkservices | sed -n '2p')"
  fi
  printf '%s\n' "$svc" > "$E2E_SNAP_DIR/primary-service.txt"
  networksetup -getdnsservers "$svc" > "$E2E_SNAP_DIR/dns-servers.txt" 2>&1 || true
  e2e_log "snapshot: purevpn=$(cat "$E2E_SNAP_DIR/purevpn.state" 2>/dev/null), service=$svc"
}

e2e_restore_state() {
  # Never let a failing restore step abort the remaining restores.
  set +e
  # A run aborted mid-scenario (e.g. by set -e on an unguarded call) can leave
  # the background `watch` process running; WATCH_PID is set by run.sh's
  # watch_start and shared into this function via the sourced shell.
  [ -n "${WATCH_PID:-}" ] && kill "$WATCH_PID" 2>/dev/null || true

  # Bring down whatever backend(s) run.sh marked as still up. The trap runs in
  # the same shell run.sh ran in, so for the common single-backend case
  # e2e_down is already defined from the earlier `source backends/$name.sh` —
  # no re-source needed. For the cross scenario (two backends possibly up),
  # E2E_ACTIVE_BACKEND holds a space-separated list in bring-up order; each
  # source overwrites the previous backend's functions, so we must re-source
  # the named backend immediately before calling ITS e2e_down, torn down in
  # reverse (last up, first down).
  if [ -n "${E2E_ACTIVE_BACKEND:-}" ]; then
    local _restore_reversed="" _b
    for _b in $E2E_ACTIVE_BACKEND; do _restore_reversed="$_b $_restore_reversed"; done
    for _b in $_restore_reversed; do
      [ -f "$E2E_ROOT/backends/$_b.sh" ] && source "$E2E_ROOT/backends/$_b.sh"
      if type e2e_down >/dev/null 2>&1; then
        e2e_down || e2e_log "WARN: restore could not bring down $_b — manual: see backends/$_b.sh"
      fi
    done
  fi

  local svc; svc="$(cat "$E2E_SNAP_DIR/primary-service.txt" 2>/dev/null)"
  if [ -n "$svc" ] && [ -f "$E2E_SNAP_DIR/dns-servers.txt" ]; then
    if grep -q "There aren't any DNS Servers" "$E2E_SNAP_DIR/dns-servers.txt"; then
      sudo -n networksetup -setdnsservers "$svc" "Empty" 2>/dev/null \
        || e2e_log "!!! DNS restore failed — run: sudo networksetup -setdnsservers '$svc' Empty"
    else
      # shellcheck disable=SC2046
      sudo -n networksetup -setdnsservers "$svc" $(cat "$E2E_SNAP_DIR/dns-servers.txt") 2>/dev/null \
        || e2e_log "!!! DNS restore failed — run: sudo networksetup -setdnsservers '$svc' <servers from $E2E_SNAP_DIR/dns-servers.txt>"
    fi
  fi
  sudo -n pkill -f "openvpn --config $E2E_ROOT/secrets" 2>/dev/null \
    || e2e_log "WARN: openvpn cleanup pkill found nothing (or failed) — if a PureVPN OpenVPN tunnel is still up, run: sudo pkill -f 'openvpn --config $E2E_ROOT/secrets'"
  if grep -q "^Connected" "$E2E_SNAP_DIR/purevpn.state" 2>/dev/null; then
    if ! scutil --nc status "PureVPN" 2>/dev/null | head -1 | grep -q Connected; then
      e2e_log "restore: attempting to reconnect PureVPN (was connected at start)"
      scutil --nc start "PureVPN" 2>/dev/null
      if e2e_poll_until "PureVPN reconnected" 20 sh -c 'scutil --nc status "PureVPN" 2>/dev/null | head -1 | grep -q Connected'; then
        e2e_log "restore: PureVPN reconnected"
      else
        e2e_log "!!! PureVPN NOT reconnected (CLI start refused by NE app — spike-verified). Reconnect manually via the PureVPN app."
      fi
    fi
  fi
  set -e
}

# --- polling -----------------------------------------------------------------
e2e_poll_until() {  # DESCRIPTION TIMEOUT_S CMD...
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    sleep 1; waited=$((waited + 1))
    [ "$waited" -ge "$timeout" ] && { e2e_log "TIMEOUT ($desc after ${timeout}s)"; return 1; }
  done
  e2e_log "$desc (after ${waited}s)"
}

e2e_status_json() {  # OUTFILE
  "$WHEREAMIP_BIN" status --json > "$1" 2>>"$E2E_LOG_DIR/run.log"
}
