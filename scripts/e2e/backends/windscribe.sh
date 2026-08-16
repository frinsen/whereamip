#!/bin/bash
# Backend: Windscribe via the v2 desktop app's bundled CLI (IPC to app engine).
# One-time setup: install Windscribe v2 app + log in (free tier ok).
E2E_EXPECTED_VPN_NAME="Windscribe"
E2E_EXPECTS_VPN=1
_ws() {
  if command -v windscribe-cli >/dev/null; then windscribe-cli "$@"; else
    "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli" "$@"
  fi
}
e2e_describe() { echo "Windscribe via windscribe-cli connect best/disconnect"; }
e2e_available() {
  { command -v windscribe-cli >/dev/null || [ -x "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli" ]; } \
    || { echo "windscribe-cli not found (install Windscribe v2 app)"; return 1; }
  _ws status >/dev/null 2>&1 || { echo "windscribe engine not running/logged in"; return 1; }
}
e2e_up() { _ws connect best; }
e2e_down() { _ws disconnect; }
