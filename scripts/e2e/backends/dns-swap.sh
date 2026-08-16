#!/bin/bash
# Backend: resolver swap via networksetup — no VPN, fully deterministic.
# Exercises resolver display + resolver-change escalation. Needs sudo.
E2E_EXPECTS_VPN=0
_dns_service() { cat "$E2E_SNAP_DIR/primary-service.txt"; }
e2e_describe() { echo "networksetup resolver swap to 9.9.9.9 on '$(_dns_service)'"; }
e2e_available() {
  [ "${E2E_SUDO:-0}" = 1 ] || { echo "needs sudo"; return 1; }
}
e2e_up() { sudo -n networksetup -setdnsservers "$(_dns_service)" 9.9.9.9; }
e2e_down() {
  if grep -q "There aren't any DNS Servers" "$E2E_SNAP_DIR/dns-servers.txt" 2>/dev/null; then
    sudo -n networksetup -setdnsservers "$(_dns_service)" "Empty"
  else
    # shellcheck disable=SC2046
    sudo -n networksetup -setdnsservers "$(_dns_service)" $(cat "$E2E_SNAP_DIR/dns-servers.txt")
  fi
}
