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
trap e2e_restore_state EXIT INT TERM

e2e_log "log dir: $E2E_LOG_DIR"
# Backends + scenarios appended by later tasks.
