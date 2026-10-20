# Psiphon integration — findings and fix plan

Research against [Psiphon-Labs/psiphon-tunnel-core](https://github.com/Psiphon-Labs/psiphon-tunnel-core) (`TunneledWebRequest` sample, `PsiphonTunnel.h`), [AzadiTunnel](https://github.com/polamgh/AzadiTunnel), and our current clients.

## What blocks IranVPN on iOS today

| Priority | Issue | Effect |
|----------|--------|--------|
| P0 | `IRANVPN_ENTITLEMENTS_SUFFIX` empty → no `packet-tunnel-provider` in the signed app | `NEConfigurationErrorDomain Code=10 permission denied` — VPN APIs never run; Psiphon in the appex never starts |
| P1 | Hardcoded minimal `getPsiphonConfig` without remote server list fields | Header: *“Remote server list functionality is not strictly required, but absence greatly undermines circumvention”* |
| P1 | `getEmbeddedServerEntries()` returns `""` | No bootstrap servers; connect fails unless remote list + keys work |
| P2 | Config not loaded from bundle files | Diverges from Psiphon’s own sample (file-based config) |
| P2 | Android `psiphonConfigJson()` omitted `PropagationChannelId` / `SponsorId` | Required by the library |

Simulator cannot host Packet Tunnel. Device builds need a **paid** Apple Developer team + Packet Tunnel on the App IDs.

## Official Psiphon iOS patterns

### A. In-app library (sample: TunneledWebRequest)

- Link `PsiphonTunnel` in the **main app** (not an NE).
- `start(true)` on foreground; use local SOCKS/HTTP for `URLSession` proxy.
- Load `psiphon-config.json` + `psiphon-embedded-server-entries.txt` from the bundle.
- README: **contact Psiphon Inc.** for Propagation/Sponsor IDs, `RemoteServerListURLs`, and signature keys.

Useful for: proving Psiphon dials work without NE signing.

### B. System VPN (Packet Tunnel) — our architecture / AzadiTunnel

- Link `PsiphonTunnel` **only** in the packet-tunnel appex (Go runtime; never with LibXray in the same process).
- Host app uses `NETunnelProviderManager` (needs NE entitlement on **app + appex**).
- Extension: start Psiphon → local SOCKS → install `NEPacketTunnelNetworkSettings` (we use PAC SOCKS for TCP).
- AzadiTunnel: copy config into an **App Group**; extension reads files (not Swift string literals). App Group is optional if the extension embeds its own Resources.

## Required Psiphon config (from `PsiphonTunnel.h`)

**Required**

- `PropagationChannelId`
- `SponsorId`

**Strongly recommended**

- `RemoteServerListURLs`
- `RemoteServerListSignaturePublicKey`
- (same key for obfuscated list if used)

**Operational**

- `ClientVersion` (stringified number)
- `EstablishTunnelTimeoutSeconds`
- `LocalSocksProxyPort` / `LocalHttpProxyPort` = `0` (dynamic)
- `DisableLocalSocksAuth` = true for PAC/local clients
- `DataStoreDirectory` — set to a writable path inside the **extension** container (NE sandbox)

Embedded server entries: non-empty file from Psiphon Inc. (or extracted from a licensed client for research). Empty → weak/no bootstrap.

## Fix checklist (in order)

1. **Apple portal** — enable Network Extensions → Packet Tunnel on:
   - `com.goldmannllc.IranVPN`
   - `com.goldmannllc.IranVPN.tunnel`
   - `com.goldmannllc.IranVPN.tunnel.xray`
2. Set `IRANVPN_ENTITLEMENTS_SUFFIX = -NetworkExtension` in `ios/Config/NetworkExtension.xcconfig` (and macOS twin). Clean rebuild on device.
3. Obtain distributor config from Psiphon Inc. (or research extraction — see AzadiTunnel `docs/BUNDLED_PSIPHON_CONFIG.md`). Put canonical files in `shared/psiphon/`, then:
   ```bash
   ./scripts/sync-psiphon-bootstrap.sh
   ```
   That updates iOS + macOS Resources, Android `assets/psiphon/`, and `windows/psiphon/psiphon.config` (SOCKS 1080 + `TargetServerEntry`).
   Optional gitignored overrides: `psiphon-config.local.json`, `psiphon-embedded-server-entries.local.txt`.
4. Confirm Connect reaches `.connected` and SOCKS probe succeeds; enable `EmitDiagnosticNotices` while debugging.
5. Android: `PsiphonPathRunner` loads assets into `startTunneling(entries)`; keep `bindToDevice` / `protect` for TUN.

## What we will not fake

- Shipping invented `RemoteServerListSignaturePublicKey` or server entries.
- Claiming Connected without NE permission + successful SOCKS probe.
- Linking Psiphon + LibXray in one process.

## References

- [PsiphonTunnel.h config contract](https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/master/MobileLibrary/iOS/PsiphonTunnel/PsiphonTunnel/PsiphonTunnel.h)
- [TunneledWebRequest sample](https://github.com/Psiphon-Labs/psiphon-tunnel-core/tree/master/MobileLibrary/iOS/SampleApps/TunneledWebRequest)
- [USAGE.md](https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/master/MobileLibrary/USAGE.md)
- [AzadiTunnel bundled config](https://github.com/polamgh/AzadiTunnel/blob/main/docs/BUNDLED_PSIPHON_CONFIG.md)
