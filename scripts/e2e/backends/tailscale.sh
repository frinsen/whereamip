#!/bin/bash
# Backend: Tailscale via the app-bundled CLI. No sudo. Exercises MagicDNS
# scoped resolver (100.100.100.100) + utun route.
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
E2E_EXPECTED_VPN_NAME="Tailscale"
E2E_EXPECTS_VPN=1
e2e_describe() { echo "Tailscale CLI up/down — MagicDNS scoped resolver, utun route"; }
e2e_available() { [ -x "$TS" ] || { echo "Tailscale.app not installed"; return 1; }; }
e2e_up() { "$TS" up; }
e2e_down() { "$TS" down; }
