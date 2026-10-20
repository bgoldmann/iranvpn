# Optional path binaries (Conduit on hold)

Conduit/in-proxy waits on Psiphon distributor keys. Until then, use:

| Provider | Setup |
|----------|--------|
| **sing-box** + Outline (`ss://`) + Hy2 | `./scripts/fetch-sing-box-android.sh` |
| **Xray** | LibXray AAR or `assets/xray/<abi>/xray` |
| **Tor** | Orbot (Advanced → Install Orbot) or `assets/tor/<abi>/tor` |
| **AmneziaWG** | Advanced import; helper binary later |
| **Psiphon** | `psiphon/` config + embedded entries (already wired) |

Binaries under `sing-box/`, `xray/`, `tor/` are **gitignored** — fetch locally before release builds.

```bash
./scripts/fetch-sing-box-android.sh
# optional:
# ./scripts/fetch-xray-android.sh
```
