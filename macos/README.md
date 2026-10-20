# Iran VPN — macOS

SwiftUI app + `IranVPNTunnel` Network Extension (Psiphon). Same probe + PAC SOCKS model as iOS.

## Setup

1. Fetch deps (shared with iOS): `./scripts/fetch-ios-tunnel-deps.sh`
2. Open `IranVPN.xcworkspace` in Xcode.
3. Targets: **IranVPN** (app) embeds **IranVPNTunnel** (`com.goldmannllc.IranVPN.tunnel`).
4. **Signing:** Default entitlements are sandbox-only (no Network Extension) so Automatic Signing works. For a real tunnel: enable **Network Extensions → Packet Tunnel** on Mac App IDs `com.goldmannllc.IranVPN` and `com.goldmannllc.IranVPN.tunnel`, then use the `*-NetworkExtension.entitlements` files.
5. UI never fakes Connected — waits for `NETunnelProviderManager` status `.connected`.

## Tunnel behavior

- Starts embedded Psiphon → local SOCKS → TCP probe → `SocksNetworkSettings` PAC to `127.0.0.1:<port>`.
- Packet flow is drained (kill-switch); TCP is forwarded via PAC, not a drop-only TUN claim without SOCKS.

## Providers on macOS

| Path | Status |
|------|--------|
| Psiphon | Default Connect (only system VPN path today) |
| Conduit / in-proxy | **On hold** — same as iOS (Psiphon keys) |
| Xray / Outline `ss://` | **Not wired yet** — need a second Packet Tunnel appex like iOS (`IranVPNTunnelXray`) |
| sing-box / Tor | Not planned until Xray appex exists — see [`docs/apple-providers.md`](../docs/apple-providers.md) |

Until the Xray appex lands, use **Android** (or Windows + binaries on PATH) for Outline / Hy2 / Tor race.

## Notes

- Notarize for Gatekeeper; distribute via GitHub Releases + mirror ([docs/distribution.md](../docs/distribution.md)).

## Architecture

```
IranVPN/
├── IranVPN.xcworkspace/
├── IranVPN.xcodeproj/          # App + IranVPNTunnel appex
├── IranVPN/                    # App shell
├── IranVPNTunnel/              # Packet Tunnel Provider
├── IranVPNPackage/             # SwiftUI feature code (VpnController, ContentView)
└── Config/                     # Shared / Debug / Release / Tunnel.xcconfig
```
