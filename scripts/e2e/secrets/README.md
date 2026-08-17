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
Native IKEv2 profile via System Settings — prompt-and-wait mode. FIELD FIND
(2026-08-17): modern macOS manages personal VPNs via NetworkExtension, so they
do NOT appear in `scutil --nc list` and CANNOT be CLI-started; the suite prompts
you to toggle and detects state via the ipsec0 interface.
1. No config file exists for IKEv2. Member area > Manual Configuration > IKEV
   gives you a server hostname (e.g. sxNNNNNN-ikev.ptoserver.com).
2. System Settings > VPN > Add VPN Configuration > IKEv2: Server address AND
   Remote ID = that hostname; User authentication = Username, with the same
   VPN credentials as purevpn.auth.
3. Name it "PureVPN AR IKEv2" (the default) or export
   E2E_PUREVPN_IKEV_SERVICE=<your name> before running the suite.
4. Nothing to store in this directory — the profile lives in System Settings.
