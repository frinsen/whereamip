# E2E secrets (gitignored — only this README is tracked)

## purevpn-ovpn backend
1. PureVPN member area → Downloads → OpenVPN configuration files (UDP).
2. Save one profile here as `purevpn.ovpn`.
3. Create `purevpn.auth` — exactly two lines: your PureVPN OpenVPN username, then password.
4. `chmod 600 purevpn.auth purevpn.ovpn`

## warp backend
`brew install --cask cloudflare-warp`, then `warp-cli registration new` (one time).

## windscribe backend
Install the Windscribe v2 desktop app and log in (free tier works).

## windscribe-wg backend
Same setup as the windscribe backend above — this variant just forces the
WireGuard protocol on connect (`windscribe-cli connect best wireguard`).

## purevpn-ikev backend
Native IKEv2 profile, driven by `scutil --nc` — this is a *different* PureVPN
service than the `purevpn-scutil`/NE-app backend, and unlike that one, CLI
start/stop actually works against it.
1. PureVPN member area → Manual Configuration → find the IKEv2 config
   (server address, IPSec identifier/shared secret, username/password).
2. macOS System Settings → Network → VPN → Add VPN → IKEv2, and fill in the
   values from step 1.
3. Name the service to match `E2E_PUREVPN_IKEV_SERVICE` (defaults to
   `PureVPN IKEV` if unset — either name it exactly that, or export
   `E2E_PUREVPN_IKEV_SERVICE=<your service name>` before running the suite).
4. No further files needed here — the profile lives in System Settings, not
   in this secrets directory.
