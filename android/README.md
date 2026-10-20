# Iran VPN — Android

Android app fallback race: **Psiphon** → **Xray** → **sing-box** → **Tor** → **Outline** (`ss://`).
**Conduit on hold** (awaiting Psiphon email reply). AmneziaWG/Rostam = Advanced-only.

```bash
./scripts/fetch-sing-box-android.sh   # Outline + Hysteria2 (required for those paths)
```

See `app/src/main/assets/README.md`.

## Build

1. **Android SDK:** Set `ANDROID_HOME` or create `local.properties` with `sdk.dir=/path/to/Android/sdk`. Copy from `local.properties.example`.
2. **tun2socks prebuilts (required):** From project root, run `./scripts/fetch-tun2socks-prebuilt.sh` to download badvpn-tun2socks libs. Run once before first build.
3. **Rust core (optional):** From project root, run `./scripts/build-android-core.sh` to build the native library. Without it, config fetch uses Java HTTP.
4. **Open in Android Studio** or run `./gradlew assembleDebug`.
5. **Release / Play:** `./gradlew assembleRelease bundleRelease`. For Play signing set `IRANVPN_KEYSTORE`, `IRANVPN_KEYSTORE_PASSWORD`, `IRANVPN_KEY_ALIAS`, `IRANVPN_KEY_PASSWORD` (env or `gradle.properties`). Without them, release still builds but is signed with the debug keystore.
6. **Play Console:** declare `FOREGROUND_SERVICE_SPECIAL_USE` (VPN), Data safety form, privacy policy URL, and VPN app category questionnaire.

`targetSdk` / `compileSdk` = 35, `versionName` = 1.0.0. Build uses Gradle 9.3.1 and AGP 8.7.2; compatible with Java 17–25.

## Psiphon integration

Psiphon Tunnel Core is enabled in `app/build.gradle.kts` (`ca.psiphon:psiphontunnel`).
`PsiphonPathRunner` implements `HostService.protectSocket` via `VpnService.protect()` so
bridge sockets do not loop into TUN. Conduit P2P is included inside Psiphon — there is
no separate Conduit path.

Bootstrap config + server entries live in `assets/psiphon/` (synced from `shared/psiphon`
via `./scripts/sync-psiphon-bootstrap.sh`). `startTunneling` receives the embedded entries.

Build with Java 17+.

## Xray integration

Prefer LibXray AAR when available. Fallback: place binary in assets:

- `assets/xray/xray`, or
- `assets/xray/<abi>/xray`

Supports VLESS+REALITY / xHTTP share links (Advanced screen). Config is written under
`noBackupFilesDir` and wiped after process start — not left cleartext in cache.

## Tunnel correctness

- MTU 1280; TUN-local DNS `198.18.0.2`; IPv6 routed into tunnel
- `addDisallowedApplication(packageName)` to prevent TUN loop
- Psiphon `HostService.loadLibrary` + `bindToDevice(long)` → `VpnService.protect`
- Probe gate (HTTPS token via SOCKS) before Connected
- Kill switch: no SOCKS ⇒ drop packets, never claim Connected
- Foreground service type: `specialUse` (VPN subtype)
- `allowBackup=false`
- UI polls service `isConnected` / `isConnecting` so Connect status stays in sync

## Packet forwarding (tun2socks)

TUN traffic is routed through SOCKS5 via badvpn-tun2socks (from universal-android-tun2socks).

**First-time setup:** Run from project root:
```bash
./scripts/fetch-tun2socks-prebuilt.sh
```
This downloads prebuilt libtun2socks.a for arm64-v8a, armeabi-v7a, x86, x86_64.

When Psiphon or Xray provides a local SOCKS5 proxy, `PacketForwarder` starts tun2socks with the TUN fd and SOCKS port. Xray supports UDP (`--socks5-udp`); Psiphon uses TCP only.
