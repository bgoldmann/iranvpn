# Iran VPN — macOS

SwiftUI app + `IranVPNTunnel` Network Extension (Psiphon). Same probe + PAC SOCKS model as iOS.

## Setup

1. Fetch deps (shared with iOS): `./scripts/fetch-ios-tunnel-deps.sh`
2. Open `IranVPN.xcworkspace` in Xcode.
3. Targets: **IranVPN** (app) embeds **IranVPNTunnel** (`com.goldmannllc.IranVPN.tunnel`).
4. Enable Network Extension entitlement / Apple capability for your team.
5. UI never fakes Connected — waits for `NETunnelProviderManager` status `.connected`.

## Tunnel behavior

- Starts embedded Psiphon → local SOCKS → TCP probe → `SocksNetworkSettings` PAC to `127.0.0.1:<port>`.
- Packet flow is drained (kill-switch); TCP is forwarded via PAC, not a drop-only TUN claim without SOCKS.

## Notes

- Xray/LibXray share links are **not** wired on macOS yet (single Go runtime / Psiphon-only appex).
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
