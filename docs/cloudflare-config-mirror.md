# Cloudflare config mirror (control plane)

IranVPN uses Cloudflare for the **config mirror** and the **first** connectivity probe, not as the default VPN data plane. If that probe fails, clients try Google `generate_204` and Firefox `success.txt` before failing Connect.
Iranian DPI often burns stable VLESS/WS+CDN domains; keep **Psiphon first**.

## What this Worker does

[`cloudflare/config-mirror/`](../cloudflare/config-mirror/) serves `server-list.json`:

1. From **R2** (`CONFIG_BUCKET` / key `server-list.json`) when bound  
2. Else **proxies** GitHub raw (`UPSTREAM_URL`) with short CDN cache  

Clients try this Worker **first**, then GitHub raw, then jsDelivr. The hostname does not resolve until the custom domain below is attached; until then clients fail over (DNS failure is fast).

## Deploy

```bash
cd cloudflare/config-mirror
npm install
npx wrangler login
npx wrangler deploy
```

Note the Workers URL, e.g. `https://iranvpn-config.<account>.workers.dev/server-list.json`.

### Custom domain (recommended)

In Cloudflare Dashboard → Workers → `iranvpn-config` → Custom Domains:

- `iranvpn-config.goldmannllc.com`

Then keep client sources pointing at:

`https://iranvpn-config.goldmannllc.com/server-list.json`

### Optional R2 (publish without waiting on GitHub)

```bash
npx wrangler r2 bucket create iranvpn-config
# Uncomment [[r2_buckets]] in wrangler.toml, redeploy
npm run publish-r2
# or: dist-config/publish.sh with CF_R2 enabled (see publish.sh)
```

## Client wiring

Hardcoded fallbacks (same order) in:

- [`android/.../ConfigFetcher.kt`](../android/app/src/main/java/org/opensignalfoundation/iranvpn/ConfigFetcher.kt)
- [`core/src/bootstrap.rs`](../core/src/bootstrap.rs)
- [`dist-config/server-list.json`](../dist-config/server-list.json)

After Connect, prefer refreshing config **via SOCKS** so clearnet GitHub blocks do not matter.

## Health

`GET /health` → `{ "ok": true, "service": "iranvpn-config" }`
