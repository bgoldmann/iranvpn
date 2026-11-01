# Distribution (US-005, FR-8)

Installers and configs must remain obtainable when GitHub and primary domains are blocked.

## Client bootstrap (no live fetch required)

1. **Embedded** Psiphon-only server list in the binary (`core` / Android `ConfigFetcher.embeddedBootstrap`).
2. **Last-good** cache on device (`noBackupFilesDir` / app config dir).
3. **Network refresh** only *after* a tunnel is up (via SOCKS).

Do not require `raw.githubusercontent.com` before first Connect.

## Installer channels (at least two)

| Channel | Use |
|---------|-----|
| GitHub Releases | Primary for developers / diaspora |
| Rotatable mirror | Second domain or CDN (jsDelivr, self-hosted S3) |
| Telegram / nearby share | Documented for users inside Iran |

### Android APK

```bash
cd android && ./gradlew assembleRelease
# Publish APK to GitHub Releases AND a mirror URL
```

### Windows

```bash
cd windows && cargo build --release
# Ship NSIS/WiX installer via Releases + mirror
```

### iOS / macOS

App Store distribution of a circumvention VPN is unlikely.
Plan: TestFlight (limited) + sideload / notarized DMG + IPA mirrors.

## Config mirrors

See [dist-config/](../dist-config/) and [cloudflare-config-mirror.md](cloudflare-config-mirror.md).

Client order (hardcoded + embedded `sources`):

1. `https://iranvpn-config.goldmannllc.com/server-list.json` (Cloudflare Worker; DNS exists only after the custom domain is attached)
2. GitHub raw
3. jsDelivr

Publish:

```bash
# Optional S3 / HTTP mirror / R2
export S3_BUCKET=...
export MIRROR_URL=https://your-mirror.example/config.json
export CF_R2=1   # uploads to R2 for the Worker (after bucket + wrangler login)
./dist-config/publish.sh

# First-time Worker deploy
cd cloudflare/config-mirror && npx wrangler deploy
# Then attach custom domain iranvpn-config.goldmannllc.com in the Dashboard
```

Sign server lists when a production Ed25519 key is configured (`core/src/bootstrap.rs`).

## Persian user guidance

- قبل از قطع اینترنت سراسری، اپ را نصب کنید.
- چند ابزار نگه دارید (Psiphon + این اپ).
- لینک‌های اشتراک را فقط از منابع مورد اعتماد بگیرید.
- از وای‌فای عمومی پرهیز کنید.

## Legal

See [legal-disclaimer.md](legal-disclaimer.md). Unauthorized VPN use is illegal in Iran.
