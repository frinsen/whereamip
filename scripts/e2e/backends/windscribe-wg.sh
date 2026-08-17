#!/bin/bash
# Backend: Windscribe forced onto WireGuard protocol — covers the WG family with a
# stable fixture (PureVPN's WG configs expire in <=24h; Windscribe's CLI selects
# protocol per-connect). Same engine/IPC requirements as windscribe.sh.
E2E_EXPECTED_VPN_NAME="Windscribe"
E2E_EXPECTS_VPN=1
_ws() {
  if command -v windscribe-cli >/dev/null; then windscribe-cli "$@"; else
    "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli" "$@"
  fi
}
e2e_describe() { echo "Windscribe via windscribe-cli connect best wireguard (WG protocol family)"; }
e2e_available() {
  { command -v windscribe-cli >/dev/null || [ -x "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli" ]; } \
    || { echo "windscribe-cli not found (install Windscribe v2 app)"; return 1; }
  _ws status >/dev/null 2>&1 || { echo "windscribe engine not running/logged in"; return 1; }
}
e2e_up() { _ws connect best wireguard; }
e2e_down() { _ws disconnect; }
