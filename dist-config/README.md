# Config distribution (FR-8)

Server list and path configs must be fetchable from **redundant** sources.
Clients **must not** depend on a live fetch for first Connect — they ship an
embedded Psiphon bootstrap and a last-good cache.

## Sources

- **Primary:** GitHub raw / S3
- **Mirror:** jsDelivr or second domain
- **Optional:** IPFS / community mirror

## Format

```json
{
  "paths": [
    { "type": "psiphon", "server_list_url": null },
    { "type": "xray", "config_json": "{...}", "subscription_url": null }
  ],
  "sources": [
    { "url": "https://mirror1.example.com/config.json", "label": "Mirror 1" }
  ]
}
```

Optional signed envelope (when Ed25519 verify key is set in the client):

```json
{
  "payload": { "paths": [...], "sources": [...] },
  "signature": "<base64 ed25519 signature over payload JSON>"
}
```

## Scripts

```bash
export S3_BUCKET=my-vpn-config
export MIRROR_URL=https://mirror.example.com/config.json
./publish.sh [server-list.json]
```

## Client order

1. Last-good cache  
2. Embedded bootstrap (`psiphon` only)  
3. Network fetch (prefer via SOCKS after connect)
