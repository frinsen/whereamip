#!/bin/bash
# Backend: PureVPN via a NATIVE IKEv2 profile (System Settings > VPN).
# FIELD-VERIFIED 2026-08-17: connects as ipsec0 (inet 10.37.5.187, v4-only tunnel,
# mtu 1280); PureVPN DNS 84.233.234.77/.79 pushed both global and ipsec0-scoped;
# DNS egress observed = 84.233.234.77 (PureVPN's own resolver — org-match calibration
# case). Remote ID = the ikev server hostname worked.
# LIMITATION (field find, 2026-08-17): modern macOS manages personal VPNs via
# NetworkExtension, NOT SystemConfiguration — they do NOT appear in `scutil --nc list`
# and cannot be started from the CLI (same wall as the PureVPN NE app, different layer).
# So this backend is prompt-and-wait: the user toggles the config in System Settings;
# state is detected via the ipsec0 interface, which only exists while an IKEv2/IPSec
# personal VPN is up.
IKEV_SERVICE="${E2E_PUREVPN_IKEV_SERVICE:-PureVPN AR IKEv2}"
E2E_EXPECTS_VPN=1
E2E_IFACE_PREFIX="ipsec"
e2e_describe() { echo "PureVPN native IKEv2 ('$IKEV_SERVICE', manual toggle) — ipsec0 interface family"; }
e2e_available() {
  # NE personal VPNs have no CLI-visible registry to probe; all we can require is an
  # interactive user who can toggle System Settings when prompted.
  [ -t 0 ] || { echo "needs interactive terminal (manual System Settings toggle)"; return 1; }
}
e2e_up() {
  e2e_log ">>> MANUAL: toggle ON '$IKEV_SERVICE' in System Settings > VPN"
  e2e_poll_until "IKEv2 tunnel up (ipsec0)" 120 sh -c 'ifconfig ipsec0 2>/dev/null | grep -q inet'
}
e2e_down() {
  e2e_log ">>> MANUAL: toggle OFF '$IKEV_SERVICE' in System Settings > VPN"
  e2e_poll_until "IKEv2 tunnel down" 120 sh -c '! ifconfig ipsec0 2>/dev/null | grep -q inet'
}
