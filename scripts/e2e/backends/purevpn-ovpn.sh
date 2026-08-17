#!/bin/bash
# Backend: PureVPN OpenVPN profile via the openvpn CLI (the vpn_connect.py
# pattern) — the field-found leaky profile itself. Needs sudo + one-time
# secrets setup (see secrets/README.md).
OVPN=/opt/homebrew/sbin/openvpn
PROFILE="$E2E_ROOT/secrets/purevpn.ovpn"
AUTH="$E2E_ROOT/secrets/purevpn.auth"   # two lines: username, password; chmod 600
PIDFILE="$E2E_LOG_DIR/openvpn.pid"
# No E2E_EXPECTED_VPN_NAME: a raw openvpn daemon has no app bundle, no SC service
# name, and a CLI-invoked tunnel carries no nameable identity — whereamip correctly
# reports vpnName=null here (field-verified 2026-08-17). Route/DNS/leak assertions
# are the meaningful checks for this backend.
E2E_EXPECTS_VPN=1
e2e_describe() { echo "PureVPN .ovpn profile via openvpn CLI (the leaky profile)"; }
e2e_available() {
  [ "${E2E_SUDO:-0}" = 1 ] || { echo "needs sudo"; return 1; }
  [ -x "$OVPN" ] || { echo "openvpn not installed"; return 1; }
  [ -f "$PROFILE" ] && [ -f "$AUTH" ] || { echo "secrets missing (see scripts/e2e/secrets/README.md)"; return 1; }
}
e2e_up() {
  sudo -n "$OVPN" --config "$PROFILE" --auth-user-pass "$AUTH" \
    --daemon --writepid "$PIDFILE" --log "$E2E_LOG_DIR/openvpn.log"
}
e2e_down() {
  [ -f "$PIDFILE" ] && sudo -n kill "$(cat "$PIDFILE")" 2>/dev/null || \
    sudo -n pkill -f "openvpn --config $PROFILE" 2>/dev/null || true
}
