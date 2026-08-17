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
