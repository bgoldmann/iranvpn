# Changelog

All notable changes to this project are documented in this file.

## [4.0.0] — 2026-10-19

### Anti-filter VPN rebuild

- **Android:** TUN correctness — `protect`/disallowed app, MTU 1280, TUN-local DNS, IPv6, kill switch, `allowBackup=false`, probe-before-Connected; Psiphon SDK linked with HostService protect; Conduit folded into Psiphon; Xray share-link/REALITY import; encrypted/wiped config files; local failure metrics.
- **Core:** Parallel race engine (~8s), probe gate, warm spare, health loop, exponential backoff; signed/embedded bootstrap + last-good cache; real DoH (SOCKS-capable); C FFI + expanded JNI.
- **Windows:** Non-blocking UI, Psiphon/Xray SOCKS race, probe gate, Wintun kill switch.
- **iOS/macOS:** Stop fake Connected; `NETunnelProviderManager` + PacketTunnelProvider probe/kill-switch; Persian UI strings.
- **Station/distribution:** Conduit launcher script; dual-channel distribution docs; embedded `server-list.json`.

## [3.0.9] — 2026-02-08

### Added

- **docs/gofundme-campaign-draft.md:** GoFundMe-style campaign draft (pro version): researched Iran internet Jan–Feb 2026 (blackout, NIN, digital isolation, Psiphon/Conduit usage), full campaign text (title, tagline, problem, why now, solution, impact numbers, use of funds, who we are, disclaimer, CTA), and four Mermaid diagrams (situation, circumvention flow, use of funds, volunteer relay).

### Fixed

- **RostamPathRunner.kt:** Corrected import from `org.opensignalfoundation.iranvpn.PathConfig` to `org.opensignalfoundation.iranvpn.model.PathConfig` so Rostam path config resolves correctly.

---

## [3.0.8] — 2026-02-06

### Changed

- **README.md (GitHub pro):** Full rewrite with badges, overview, feature list; Mermaid diagrams for repository layout, high-level client flow, Iran filtering system, and circumvention flow; project structure table, build instructions, report TOC, quick links table, and legal notice. Keeps existing report/changelog/PRD links.

---

## [3.0.7] — 2026-02-06

### Fixed

- **Android build with Java 25:** Upgraded Gradle to 9.3.1 and AGP to 8.7.2; resolves "25.0.1" build failure when using JDK 25.

### Added

- **local.properties.example:** Template for sdk.dir when ANDROID_HOME is not set.

---

## [3.0.6] — 2026-02-06

### Added

- **tun2socks integration (Android):** PacketForwarder uses badvpn-tun2socks (from universal-android-tun2socks) to route TUN traffic through SOCKS5. Tun2SocksNative JNI bridge; prebuilts fetched via `scripts/fetch-tun2socks-prebuilt.sh`. SocksProxyProvider.supportsUdp() for Xray UDP.
- **PacketForwarder.stop():** Called on disconnect to terminate tun2socks cleanly.

### Changed

- PacketForwarder: When socksPort > 0, runs tun2socks in background thread instead of dropping packets.
- SocksProxyProvider: Added supportsUdp() (default false); XrayPathRunner returns true.

---

## [3.0.5] — 2026-02-06

### Added

- **XrayPathRunner (Android):** Subprocess-based Xray integration; extracts binary from assets/xray/; writes config, starts xray run -c; implements SocksProxyProvider. Supports subscription URL fetch. Requires xray binary in assets.

### Changed

- ConduitPathRunner: Clarified that Psiphon includes Conduit; standalone Conduit pending.
- PathConfig.XrayConfig: configJson optional (optString) when subscription_url provided.

---

## [3.0.4] — 2026-02-06

### Added

- **Android packet forwarding:** SocksProxyProvider interface; PsiphonPathRunner implements it. PacketForwarder reads TUN packets; structure ready for tun2socks integration (TODO).
- **iOS packet flow:** PacketTunnelProvider reads from packetFlow in a loop; forwardPackets placeholder for Psiphon/Xray/Rostam integration.
- **Windows packet loop:** Wintun session stores adapter+session; spawns packet thread with try_receive loop; stop_wintun_tunnel shuts down cleanly.

### Changed

- VpnTunnelService: Uses PacketForwarder with SOCKS port from SocksProxyProvider; runs read loop per connected path.

---

## [3.0.3] — 2026-02-06

### Added

- **Psiphon integration (Android):** PsiphonPathRunner with reflection-based optional Psiphon SDK; HostService proxy, startTunneling/stop, SOCKS proxy mode. Psiphon Maven repo in settings; uncomment dependency to enable.
- **Gradle wrapper:** Added gradlew and gradle-wrapper.jar for Android builds.
- **android/README.md:** Build instructions, Psiphon setup, Java 17 note.

### Changed

- VpnTunnelService: Fixed activeRunner to use the actual connected runner (from orchestrator) for proper disconnect.
- PsiphonPathRunner: Requires Context; uses reflection when Psiphon SDK is on classpath.

---

## [3.0.2] — 2026-02-06

### Added

- **scripts/build-android-core.sh:** Build Rust core for Android (cargo-ndk or manual); outputs to `android/app/src/main/jniLibs/`.
- **Windows:** Wintun TUN integration in demo mode (`IRAN_VPN_DEMO=1`); Wintun gated as `[target.'cfg(target_os = "windows")'.dependencies]` for cross-platform workspace builds.

### Changed

- README: Android build now documents `build-android-core.sh`.
- Windows README: Added demo mode run instructions.

---

## [3.0.1] — 2026-02-06

### Added

- Core: `fallback_server_list()` for bootstrap when all config sources fail; Windows and Android use it.

### Fixed

- Android: Added missing `fallbackServerList()` in ConfigFetcher (used when all config sources fail).
- Windows: Simplified `run_connect()`—removed redundant nested tokio runtime; uses core `fallback_server_list()` when fetch fails.

### Changed

- macOS: ContentView updated with full legal disclaimer, Connect/Disconnect UI, and active path display; README expanded with Iran VPN setup instructions.

---

## [3.0.0] — 2026-02-06

### Added

- **Core:** Fixed missing `pub mod fetch;`; added `default_config_sources()` for zero-config (FR-8).
- **Android:** Full fallback chain integration: ConfigFetcher, FallbackOrchestrator, PathRunners (Psiphon, Conduit, Xray, Rostam), VpnTunnelService with fetch→fallback flow, ConnectScreen with active path display, JNI bridge stub (Native.kt).
- **iOS:** Full Xcode project (IranVPN workspace), ContentView with Connect/Disconnect and legal disclaimer, PacketTunnelProvider scaffold (IranVPNTunnel/), Network Extension entitlements.
- **Windows:** Rust app with egui UI, Wintun, core integration, legal disclaimer, WindowsPathRunner stub.
- **macOS:** Full Xcode project, ContentView, Network Extension entitlements.
- **dist-config:** Implemented `publish.sh` with S3 and mirror upload (env: S3_BUCKET, MIRROR_URL).
- **scripts:** `build-core.sh` for multi-target core builds.

### Changed

- Android: VpnTunnelService uses FallbackOrchestrator and ConfigFetcher; ConnectScreen shows active path.
- dist-config README: Added publish instructions and default ConfigSource URLs.

---

## [2.0.0] — 2026-02-06

### Added

- **Core (Rust):** `core/` library with config types (VLESS, VMess, Trojan, Rostam/WireGuard), fallback engine (ordered paths, health check, &lt;15s switch, exponential backoff), DoH client stub, protocol registry, config fetch from redundant sources (FR-8).
- **Android app:** `android/` Kotlin + Jetpack Compose app: Connect/Disconnect, VpnTunnelService with TUN interface, legal disclaimer on first launch (US-008), ConnectScreen with status.
- **iOS scaffold:** `ios/` README and ContentView (SwiftUI) placeholder for NetworkExtension and core integration.
- **Windows scaffold:** `windows/` README for Wintun + core.
- **macOS scaffold:** `macos/` README for NEPacketTunnelProvider + core.
- **Station:** `station/` README for volunteer P2P (Conduit-style) (US-004).
- **Config distribution:** `dist-config/` README and publish script placeholder for decentralized server list (FR-8).
- **Docs:** `docs/legal-disclaimer.md` (US-008), `docs/protocol-integration.md` (US-007).

### Changed

- README expanded with app structure, build instructions, and links to PRD and docs.

---

## [1.3.1] — 2026-02-06

### Changed

- Expanded prd.md with SKILL-aligned structure: Introduction/Overview, User Stories (US-001–US-008), Design Considerations, Open Questions
- Added prd.json companion file with structured user stories for task tracking

---

## [1.3.0] — 2026-02-06

### Added

- PRD for bullet-proof improved VPN for Iran filtering evasion (prd.md)

---

## [1.2.0] — 2026-02-06

### Added

- GitHub newest VPN tech report (08-github-newest-vpn-tech-2026.md)

---

## [1.1.0] — 2026-02-06

### Added

- Complete report with pros/cons and improvement recommendations (07-complete-report-pros-cons-improvements.md)

---

## [1.0.0] — 2026-02-06

### Added

- Project README with links to Iran VPN Research Report 2026
- Full report structure under `report-iran-vpn-2026/`:
  - Executive summary
  - Iran filtering system analysis with mermaid diagram
  - VPN circumvention techniques with flow diagram
  - Open source solutions with comparison table and tool selection diagram
  - Recommendations and legal disclaimer
  - References
