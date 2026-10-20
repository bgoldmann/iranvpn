# FOSS providers to strengthen IranVPN — research (Oct 2026)

Goal: find **free and open-source** circumvention stacks we can add (or deepen) so Connect stays resilient when Psiphon direct or Xray alone fails. Based on web research (Tor Project 2025 Iran/Russia notes, TechRadar Jan 2026 Iran coverage, Javid Network Watch, Amnezia, Geph, Lantern, Hiddify, Mahsa/Nika, MoaV protocol catalog) plus this repo’s existing `report-iran-vpn-2026/` and path runners.

**Legal note:** Research/informational only. Unauthorized VPN use is illegal in Iran; users assume risk.

---

## What we already have

| Path | Role | Gap |
|------|------|-----|
| **Psiphon** (+ Conduit in-proxy) | Zero-config network | Needs distributor secrets for strong Conduit |
| **Xray / LibXray** | VLESS/VMess/Trojan/REALITY/xHTTP via share link | Needs user or subscription configs |
| **Rostam** (stub) | Obfuscated WireGuard | Not in default race; UDP whitelist risk |
| **Conduit PathRunner** | Stub | Wrong model — fold into Psiphon |

---

## Ranking: best FOSS additions for *this* app

Criteria: FOSS license, Iran relevance, embeddability (SOCKS → our TUN), zero-config vs needs servers, mobile/desktop fit, maintainer health.

| Priority | Provider / stack | FOSS? | Zero-config network? | Fit for IranVPN | Effort |
|----------|------------------|-------|----------------------|-----------------|--------|
| **P0** | Finish **Psiphon Conduit** (in-proxy) | Yes (GPL) | Yes (Psiphon network) | Already wired; unlock with keys | Low–med (keys) |
| **P0** | Harden **Xray** + subscription fetch | Yes (MPL/MIT cores) | No (need nodes) | Already partial | Low |
| **P1** | **sing-box** (Hysteria2, TUIC, Reality, SS2022) | GPL-3.0 | No | One binary replaces multi-protocol race | Med–high |
| **P1** | **Tor + Snowflake / WebTunnel** (Orbot-style) | BSD/GPL-ish | Yes (Tor network + volunteers) | Strong shutdown backup; SOCKS | Med |
| **P1** | **AmneziaWG** / Amnezia client protocols | Open source | Free tier + self-host | Obfuscated WG; Iran-tested narrative | Med |
| **P2** | **Outline** (Shadowsocks) | Apache-2.0 | No (need Outline server) | Easy self-host for orgs | Med |
| **P2** | **Geph** | Open source (Rust) | Geph network (freemium model) | Circumvention-first; API/client | Med–high |
| **P2** | **NaiveProxy** | BSD-style | No (need Caddy+Naive) | Excellent TLS fingerprint; niche | Med |
| **P3** | **Lantern / Unbounded** | OSS client; network proprietary-ish | Lantern network | Deep-link better than embed | Low (CTA) |
| **P3** | **RostamWG** | Iran-focused WG | No | Finish PathRunner behind TLS | Med |
| **Avoid as “provider”** | MahsaNG free configs | Client partly closed | Mahsa servers | ToS/abuse; not fully OSS provider | — |
| **Use as reference** | NikaNG / Mahsa-core | Yes | No | Fragment/WARP ideas via Xray/sing-box | — |

---

## Deep dive by category

### A — Volunteer / bootstrap networks (no your own VPS)

These matter most during **national shutdowns** when datacenter IPs die.

#### 1. Psiphon Conduit (in-proxy) — keep #1
- **What:** Residential volunteer relays inside Psiphon tunnel-core.
- **Why:** Proven Iran scale (TechRadar / Psiphon 2026 reporting).
- **How for us:** Not a new PathRunner — distributor keys + optional personal compartment ([`docs/conduit-integration.md`](conduit-integration.md)).
- **Station:** Deep-link official Conduit app; don’t reimplement.

#### 2. Tor Snowflake (+ WebTunnel, obfs4)
- **What:** WebRTC volunteer proxies into Tor; WebTunnel = HTTPS-looking bridges; obfs4 = classic bridges.
- **FOSS:** Tor Project; [Snowflake](https://snowflake.torproject.org/); Orbot on Android.
- **Iran notes:** Tor Project (2025) calls Snowflake heavily used in Iran; also reports periods of blocking / OONI anomalies — still worth a **fallback**. WebTunnel growing (TechRadar / Tor Telegram bridges).
- **How for us:**
  - **Android:** Optional path via Orbot Intent / Orbot VPN API, or embed lyrebird + tor SOCKS (heavy).
  - **iOS:** Hard (no official Tor Browser; Onion Browser exists; NE + Tor is non-trivial). Prefer “Open Orbot / Tor Browser” CTA or SOCKS to local Orbot if installed.
  - **Desktop:** Bundle `tor` + Snowflake client config → local SOCKS → existing probe gate.
- **Strength:** Independent of Psiphon; volunteer pool different from Conduit.

#### 3. Lantern Unbounded
- **What:** Browser/extension volunteer relays (Lantern).
- **FOSS:** Client OSS ([getlantern/lantern](https://github.com/getlantern/lantern)); network ops not a drop-in SDK.
- **How for us:** In-app link to Lantern download; do **not** try to vendor their network.

#### 4. Geph
- **What:** Modular censorship circumvention ([geph-official/geph4-client](https://github.com/geph-official/geph4-client), Rust).
- **How for us:** Evaluate embedding `geph4-client` as SOCKS path; check license + whether free tier allows redistribution of credentials. Likely **optional Advanced** path if API is clean.

---

### B — Protocol engines (need configs / subscriptions)

Expand beyond “one Xray JSON” so imported links and org-run nodes survive DPI changes.

#### 5. sing-box (highest leverage multi-protocol)
- **GitHub:** [SagerNet/sing-box](https://github.com/SagerNet/sing-box) (~30k★, GPL-3.0)
- **Protocols:** VLESS/Reality, Hysteria2, TUIC, Shadowsocks-2022, Trojan, WireGuard, Naive, ShadowTLS, SSH, …
- **Clients to study:** [Hiddify](https://github.com/hiddify/hiddify-app) (multi-platform, sing-box based).
- **How for us:**
  - Replace or sit beside LibXray with **Libbox / sing-box** in a dedicated appex/process (same Go-runtime rule as Psiphon vs Xray).
  - Accept **sing-box / Clash Meta / Hiddify** subscription URLs in Advanced.
  - Enables **Hysteria2** (QUIC/HTTP3 — fast when UDP open; may fail when UDP blocked in Iran).
- **License caution:** GPL → IranVPN linking implications (already using GPL Psiphon on some platforms).

#### 6. Xray-core (already in tree) — deepen
- Reality, xHTTP, fragment (Mahsa-core ideas via open NikaNG/Mahsa-core).
- **How:** Reliable LibXray on Android/iOS; subscription auto-fetch; prefer Reality share links in docs.
- **Don’t** depend on MahsaNG’s closed config encryption for our zero-config.

#### 7. Hysteria 2 / TUIC (via sing-box preferred)
- Standalone [apernet/hysteria](https://github.com/apernet/hysteria) (MIT) or TUIC (GPL).
- Prefer **one** engine (sing-box) over three Go binaries.

#### 8. NaiveProxy
- [klzgrad/naiveproxy](https://github.com/klzgrad/naiveproxy) — Chromium TLS stack; hard to fingerprint.
- **How:** Advanced-only; user supplies Naive URL; or sing-box Naive outbound if available.
- Needs operator-run Caddy ForwardProxy — good for NGO self-host, not zero-config masses.

#### 9. Outline (Shadowsocks)
- [Jigsaw Outline](https://getoutline.org/) — Apache-2.0 client/server; easy invite keys.
- **How:** Parse `ss://` Outline access keys → SOCKS via Outline or sing-box SS2022.
- Strength: org/activist self-host story; weak as sole Iran mass path (SS often probed).

#### 10. AmneziaWG / Amnezia
- [amnezia.org](https://amnezia.org/) — AmneziaWG 3.1 + Xray Reality etc.; audits (7ASecurity).
- App FOSS; **Amnezia Free** is a service (not your servers).
- **How:**
  - Implement **AmneziaWG** as Rostam-class path (obfuscated WG) when we have configs.
  - Or deep-link Amnezia app; or import Amnezia config format in Advanced.
- Complements Reality (TCP/TLS) when UDP WG fails.

#### 11. RostamWG
- Already in PRD/config; PathRunner stub.
- **How:** Finish only with **TLS/WS wrap** or AmneziaWG-style obfuscation — raw WG loses to Iran whitelist (our own RostamPathRunner comment).

---

### C — Iran-ecosystem clients (learn from, don’t vendor blindly)

| Project | License / openness | Takeaway for IranVPN |
|---------|--------------------|----------------------|
| **NikaNG** | Fully OSS (Mahsa-core) | Fragment, WARP, WG noise — implement via Xray/sing-box options |
| **MahsaNG** | Client partly closed (config crypto) | Free rotating configs **not** a clean FOSS provider to embed |
| **Hiddify** | OSS multi-platform | UX + sing-box integration patterns |
| **Nova Server** | Self-host panel (Xray+sing-box+AWG) | Ops side for diaspora-run nodes, not client embed |

---

### D — Last-resort / niche (document, rarely embed)

| Tool | Notes |
|------|-------|
| **dnstt / Slipstream** (DNS tunnel) | Tiny bandwidth; MoaV lists as last resort |
| **Conjure** | Refraction networking; research/ops heavy |
| **meek** (CDN fronting) | Slow; Tor/Psiphon already cover similar ideas |
| **WARP** (Cloudflare) | Not FOSS network; Nika uses as option — license/ToS careful |

---

## Recommended roadmap for IranVPN

See also **[`provider-expansion-plan.md`](provider-expansion-plan.md)** (implementation status).

### Near term — in progress / done in tree
1. **Psiphon distributor keys** → still need [sponsor@psiphon.ca](mailto:sponsor@psiphon.ca) for full network Conduit.
2. **Conduit personal pairing** UI + `InproxyClientPersonalCompartmentID` injection (Android + iOS).
3. **Xray** share/subscription race when binary present.
4. **sing-box / Tor / Outline / AmneziaWG** PathRunners + Advanced import (binaries optional under `assets/`).

### Medium term
5. Bundle release binaries for sing-box (and optional Tor) on Android.
6. iOS Outline `ss://` via LibXray (**done**); macOS Xray appex; sing-box / Tor NE or deep-link — see [`apple-providers.md`](apple-providers.md).
7. AmneziaWG SOCKS bridge when `amneziawg-go` is vendored.

### Volunteer / diaspora (ops, not Connect race)
8. Keep **Conduit** + add **Snowflake proxy** CTA in `station/` (browser extension / standalone).
9. Optional docs for Outline/Amnezia/Nova self-host for NGOs.

### Do not
- Embed MahsaNG closed config pipeline.
- Race a fake “Conduit” PathRunner.
- Ship plain OpenVPN / plain WireGuard as default.
- Claim zero-config for protocols that need private VPS keys.

---

## Architecture sketch (target race)

```text
Connect
  ├─ Psiphon (direct + in-proxy/Conduit)     ← zero-config network
  ├─ Tor/Snowflake (optional)                ← zero-config volunteer
  ├─ sing-box / Xray (subscription/share)    ← user or org nodes
  └─ AmneziaWG / Rostam (optional Advanced)  ← user node
```

Each path still: local SOCKS → probe gate → TUN/PAC → kill switch.

---

## Sources

- [Tor Project — Iran/Russia 2025](https://blog.torproject.org/staying-ahead-of-censors-2025/)
- [TechRadar — Iran circumvention (Psiphon, Snowflake, Lantern)](https://www.techradar.com/vpn/vpn-privacy-security/iranians-are-resilient-they-always-find-ways-to-speak-how-iranians-are-overcoming-unprecedented-internet-censorship)
- [Javid Network Watch — Iran digital freedom resources](https://javidnetworkwatch.com/resources)
- [Amnezia](https://amnezia.org/) · [Geph](https://github.com/geph-official/geph4-client) · [Lantern](https://github.com/getlantern/lantern)
- [Hiddify](https://github.com/hiddify/hiddify-app) · [sing-box](https://github.com/SagerNet/sing-box) · [Hysteria](https://github.com/apernet/hysteria)
- [NikaNG](https://github.com/mahsanet/NikaNG) · [MahsaNG](https://github.com/GFW-knocker/MahsaNG/)
- [MoaV client/protocol catalog](https://moav.sh/docs/CLIENTS/)
- Repo: `report-iran-vpn-2026/08-github-newest-vpn-tech-2026.md`, `docs/conduit-integration.md`

---

## Open decisions

1. Prefer **sing-box** as second engine vs deepen **Xray-only**?
2. Is **Tor/Snowflake** worth APK size / review risk on Android?
3. Contact **Psiphon** (sponsor) and/or **Geph** for redistributable free configs?
4. GPL stacking (Psiphon + sing-box) vs keep MIT wrapper + separate GPL processes only?
