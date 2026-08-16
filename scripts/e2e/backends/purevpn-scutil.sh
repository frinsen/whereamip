#!/bin/bash
# Backend: PureVPN via scutil --nc against the app's NE profile.
# Spike 2026-08-16: REFUSED — stop worked, start did not; NE app did not auto-reconnect within 60s+ poll window.
# Evidence: scutil --nc stop transitions to Disconnected in ~60s; scutil --nc start transitions Connecting → Connecting → Disconnected without reaching Connected.
E2E_EXPECTED_VPN_NAME="PureVPN"
E2E_EXPECTS_VPN=1
e2e_describe() { echo "PureVPN via scutil --nc start/stop (NE app profile)"; }
e2e_available() {
  scutil --nc list 2>/dev/null | grep -q '"PureVPN"' || { echo "no PureVPN NE service"; return 1; }
}
e2e_up() {
  e2e_log ">>> MANUAL: please CONNECT PureVPN in the app (CLI start refused by NE)"
  e2e_poll_until "PureVPN connected" 90 sh -c 'scutil --nc status "PureVPN" | head -1 | grep -q Connected'
}
e2e_down() {
  scutil --nc stop "PureVPN"
}
