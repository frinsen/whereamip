#!/bin/bash
# Backend: Cloudflare WARP via warp-cli. DNS egresses via 1.1.1.1 INSIDE the
# tunnel — DNS egress != tunnel exit is EXPECTED healthy behavior here, so
# leak verdicts from this backend are calibration gold (spec §1).
# One-time setup: brew install --cask cloudflare-warp && warp-cli register
E2E_EXPECTS_VPN=1
e2e_describe() { echo "Cloudflare WARP via warp-cli connect/disconnect"; }
e2e_available() {
  command -v warp-cli >/dev/null || { echo "warp-cli not installed (brew install --cask cloudflare-warp)"; return 1; }
  warp-cli --accept-tos status >/dev/null 2>&1 || { echo "warp-cli present but not registered (warp-cli register)"; return 1; }
}
e2e_up() { warp-cli --accept-tos connect; }
e2e_down() { warp-cli --accept-tos disconnect; }
