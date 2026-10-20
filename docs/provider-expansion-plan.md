# Provider expansion plan

Sequence: **finish Psiphon Conduit + Xray**, then add the rest of useful FOSS providers from [`foss-providers-research.md`](foss-providers-research.md).

## Phase A — Finish (required foundation)

| Item | Status target |
|------|----------------|
| Psiphon bootstrap entries + IDs | Done (shared/psiphon) |
| Conduit = in-proxy inside Psiphon | **ON HOLD** — email sent to Psiphon (`sponsor@psiphon.ca`); personal-compartment UI ready; wait for distributor keys |
| Xray share links + subscription URL | Race when LibXray/binary present; parsers for vless/vmess/trojan/https sub |

## Phase B — Add next providers (this implementation)

Default race when assets/binaries + user config exist:

```text
Psiphon (+ Conduit/in-proxy)
  → Xray (share / subscription)
  → sing-box (Hysteria2 / Reality / multi)
  → Tor/Snowflake (local tor SOCKS or bridges)
  → Outline (ss://)
```

Advanced-only (not default race until binary + config):

```text
AmneziaWG / Rostam (obfuscated WireGuard)
```

| Provider | Config | Binary / SDK | Platforms first |
|----------|--------|--------------|-----------------|
| sing-box | JSON or share → sing-box | `assets/sing-box/<abi>/sing-box` | Android → desktop |
| Tor | bridge lines / use system Orbot | `assets/tor/` or Orbot Intent | Android |
| Outline | `ss://` access key | Android: sing-box/Outline; iOS: LibXray shadowsocks | Android + iOS; macOS TBD |
| AmneziaWG | AWG/INI config | `assets/amneziawg` / `awg` | Android Advanced |

## Phase C — Apple (see [`apple-providers.md`](apple-providers.md))

- iOS: Xray + `ss://` via LibXray (**done**); Libbox appex later for Hy2
- macOS: add `IranVPNTunnelXray` parity with iOS (next Apple milestone)
- Tor on Apple: deep-link / external only for now

## Phase D — Later

- Geph / NaiveProxy / Lantern CTA
- Snowflake proxy CTA in `station/`

## Rules

- Never claim Connected without SOCKS probe.
- One Go runtime per process (Psiphon ≠ LibXray ≠ sing-box process).
- No MahsaNG closed config pipeline.
- Distributor secrets stay in `*.local.json` (gitignored).
