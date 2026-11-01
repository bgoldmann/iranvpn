# Cloudflare config mirror (control plane)

IranVPN uses Cloudflare for the **config mirror** and the **first** connectivity probe, not as the default VPN data plane. If that probe fails, clients try Google `generate_204` and Firefox `success.txt` before failing Connect.
Iranian DPI often burns stable VLESS/WS+CDN domains; keep **Psiphon first**.

## What this Worker does

[`cloudflare/config-mirror/`](../cloudflare/config-mirror/) serves `server-list.json`:

1. From **R2** (`CONFIG_BUCKET` / key `server-list.json`) when bound  
2. Else **proxies** GitHub raw (`UPSTREAM_URL`) with short CDN cache  

Clients try this Worker **first**, then GitHub raw, then jsDelivr. The custom domain `iranvpn-config.goldmannllc.com` is attached and serves the list. A body that is not a server list (missing `paths`, empty `paths`, or no `type` on a path) is not served; the client then tries the next source.

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

### R2

The Worker is bound to the `iranvpn-config` bucket and serves `server-list.json` from R2 when that object is a server list. A missing or invalid object falls through to GitHub.

```bash
npx wrangler r2 bucket create iranvpn-config   # already created
npm run publish-r2
# or: CF_R2=1 ../../dist-config/publish.sh
```

## Client wiring

Hardcoded fallbacks (same order) in:

- [`android/.../ConfigFetcher.kt`](../android/app/src/main/java/org/opensignalfoundation/iranvpn/ConfigFetcher.kt)
- [`core/src/bootstrap.rs`](../core/src/bootstrap.rs)
- [`dist-config/server-list.json`](../dist-config/server-list.json)

After Connect, prefer refreshing config **via SOCKS** so clearnet GitHub blocks do not matter.

## Health

`GET /health` → `{ "ok": true, "service": "iranvpn-config" }`
