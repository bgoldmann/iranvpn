# Volunteer P2P station (US-004)

This project does **not** invent a new P2P overlay. Volunteers should run the
official **Psiphon Conduit** station. This folder provides a thin launcher and
docs so diaspora/allies can share bandwidth with users in Iran.

## Official Conduit

| Resource | URL |
|----------|-----|
| Website | https://conduit.psiphon.ca/ |
| GitHub | https://github.com/Psiphon-Inc/conduit |
| Security | Cure53 audit (see Conduit docs) |

Traffic is end-to-end encrypted; volunteers cannot see content.

## Quick start

### Android / Windows / macOS

1. Download Conduit from [conduit.psiphon.ca](https://conduit.psiphon.ca/) or GitHub Releases.
2. Or run the helper script from this repo:

```bash
./station/launch-conduit.sh
```

3. Prefer stable home Wi‑Fi / unlimited data.
4. Set bandwidth and battery limits in Conduit settings.

### iOS

Conduit iOS station support is **not available** yet (Psiphon roadmap).
iOS users of Iran VPN use Psiphon direct + imported Xray only — not volunteer stations.

## Status UI (planned wrapper)

When wrapping Conduit, show:

- Connected users
- Throughput
- Bandwidth / battery limits
- Link to Cure53 audit

Until a wrapper ships, use Conduit’s own UI.

## Why Conduit matters

During severe Iran shutdowns, direct international routes may die. Conduit
exploits volunteer egress that censors cannot fully close without collateral
damage. In Jan 2026, a large share of Psiphon Iran traffic used Conduit.
