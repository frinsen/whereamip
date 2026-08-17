#!/bin/bash
# Backend: PureVPN via a NATIVE IKEv2 profile (System Settings > VPN import) driven by
# scutil --nc — unlike the NE app (spike: start refused), native profiles accept CLI
# start/stop. Exercises the ipsec0 interface family — never field-tested before this.
# One-time setup: member area > Manual Configuration > IKEV config; import in System
# Settings > VPN; service name must match E2E_PUREVPN_IKEV_SERVICE (default below).
IKEV_SERVICE="${E2E_PUREVPN_IKEV_SERVICE:-PureVPN IKEV}"
E2E_EXPECTS_VPN=1
E2E_IFACE_PREFIX="ipsec"
e2e_describe() { echo "PureVPN native IKEv2 via scutil --nc ('$IKEV_SERVICE') — ipsec interface family"; }
e2e_available() {
  scutil --nc list 2>/dev/null | grep -q "\"$IKEV_SERVICE\"" || { echo "no native IKEv2 service '$IKEV_SERVICE' (import config in System Settings, or set E2E_PUREVPN_IKEV_SERVICE)"; return 1; }
}
e2e_up() { scutil --nc start "$IKEV_SERVICE"; }
e2e_down() { scutil --nc stop "$IKEV_SERVICE"; }
