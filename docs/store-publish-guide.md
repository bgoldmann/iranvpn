# Iran VPN — Store publish guide

Step-by-step listing copy, links, and upload checklist for **App Store** and **Google Play**.

**Primary publisher site:** [https://goldmannllc.com](https://goldmannllc.com) (Goldmann LLC — matches iOS `com.goldmannllc.*`).

**Do not use** [goldmann.com](https://goldmann.com) (unrelated personal site).

| Role | URL |
|------|-----|
| Company home | [https://goldmannllc.com](https://goldmannllc.com) |
| Iran VPN product page | [https://goldmannllc.com/websites/iranvpn](https://goldmannllc.com/websites/iranvpn) |
| Privacy Policy | [https://goldmannllc.com/privacy](https://goldmannllc.com/privacy) → `/legal/privacy` |
| Terms of Use | [https://goldmannllc.com/terms](https://goldmannllc.com/terms) → `/legal/terms` |
| Support / contact | [https://goldmannllc.com/contact](https://goldmannllc.com/contact) |
| Optional research homepage | [https://www.opensignalfoundation.org/projects/iranvpn](https://www.opensignalfoundation.org/projects/iranvpn) |

---

## 1. Copy-paste: titles, subtitle, keywords

### App Store (Apple)

| Field | Limit | Recommended |
|-------|-------|-------------|
| **Name** | 30 chars | `Iran VPN` |
| **Subtitle** | 30 chars | `One-tap secure access` |
| **Promotional text** | 170 | Optional; change anytime without a new build |
| **Keywords** | 100 chars, comma-separated, **no spaces after commas** | see below |

**Keywords (≤100 characters):**

```
vpn,iran,privacy,proxy,psiphon,secure,tunnel,censorship,dns,network,wifi,unblock
```

Character count: 96 (leave room; do not repeat words already in Name/Subtitle — Apple merges them).

**Alternate Name options** (if `Iran VPN` is taken):

- `IranVPN`
- `Iran VPN Secure`

**Alternate Subtitle options:**

- `Private tunnel, one tap`
- `Research-grade VPN client`

### Google Play

| Field | Limit | Recommended |
|-------|-------|-------------|
| **App name** | 30 chars | `Iran VPN` |
| **Short description** | 80 chars | `One-tap VPN with automatic path fallback for filtered networks.` |
| **Full description** | 4000 | see §3 |

Play has **no keyword field**. Put search terms naturally in short + full description and in the title once.

---

## 2. Required store URLs — Goldmann LLC primary

Use these in App Store Connect and Play Console:

| ASC / Play field | URL |
|------------------|-----|
| **Privacy Policy** | [https://goldmannllc.com/privacy](https://goldmannllc.com/privacy) |
| **Marketing / website** | [https://goldmannllc.com/websites/iranvpn](https://goldmannllc.com/websites/iranvpn) |
| **Support URL** | [https://goldmannllc.com/contact](https://goldmannllc.com/contact) |
| **Terms of Use** | [https://goldmannllc.com/terms](https://goldmannllc.com/terms) |

### Contact emails (from goldmannllc.com)

| Purpose | Email |
|---------|-------|
| App support | `support@goldmannllc.com` |
| Privacy | `privacy@goldmannllc.com` |
| Legal | `legal@goldmannllc.com` |
| Security | `security@goldmannllc.com` |
| Phone | +1 (949) 264-2004 |

### Optional secondary links (Open Signal Foundation)

Only if you want a research/nonprofit cite in the long description:

| Field | URL |
|-------|-----|
| Research project | [https://www.opensignalfoundation.org/projects/iranvpn](https://www.opensignalfoundation.org/projects/iranvpn) |
| Safety notice | [https://www.opensignalfoundation.org/safety](https://www.opensignalfoundation.org/safety) |

### Seller / developer identity

| Store | Seller name | Bundle / application ID |
|-------|-------------|-------------------------|
| **App Store** | **Goldmann LLC** | `com.goldmannllc.IranVPN` (+ `.tunnel`, `.tunnel.xray`) |
| **Google Play** | Prefer **Goldmann LLC** for consistency; package is still `org.opensignalfoundation.iranvpn` | `org.opensignalfoundation.iranvpn` |

**Recommendation:** list Goldmann LLC as seller on both stores; keep package IDs as-is (changing Android `applicationId` is a new Play listing).

---

## 3. Description drafts

### App Store — Description

```
Iran VPN is an open-source client for safer access to information on filtered networks.

• One tap to connect — no server setup for the default path
• Automatic protocol fallback when a path fails
• Optional import of share links (advanced)
• Kill switch: does not claim Connected until the tunnel is ready
• Built for research and digital-safety education

Publisher: Goldmann LLC
https://goldmannllc.com/websites/iranvpn

Privacy: https://goldmannllc.com/privacy
Support: https://goldmannllc.com/contact
Terms: https://goldmannllc.com/terms

Research partner: Open Signal Foundation
https://www.opensignalfoundation.org/projects/iranvpn

IMPORTANT: Laws and risks differ by country. Unauthorized VPN use may be illegal in some jurisdictions. This app does not guarantee anonymity or access.
```

### App Store — What’s New (1.0.0)

```
Initial release: Psiphon path, optional Xray share links, one-tap connect, and kill-switch probe before Connected.
```

### Google Play — Short description (80)

```
One-tap VPN with automatic path fallback for filtered networks.
```

### Google Play — Full description

```
Iran VPN helps you reach open information on highly filtered networks.

WHAT YOU GET
• One-tap connect with zero server setup on the default path
• Automatic fallback across supported tunnel paths
• Optional advanced share-link import
• Foreground VPN service with clear Connected / Connecting status
• Published by Goldmann LLC; open-source research with Open Signal Foundation

LINKS
Website: https://goldmannllc.com/websites/iranvpn
Privacy: https://goldmannllc.com/privacy
Terms: https://goldmannllc.com/terms
Support: https://goldmannllc.com/contact
Research: https://www.opensignalfoundation.org/projects/iranvpn

KEYWORDS (for readers, not a separate Play field)
VPN, Iran, privacy, secure tunnel, proxy, filtered network, Psiphon, digital safety

LEGAL
Unauthorized VPN use may be illegal in some countries. This app is for research and informational use. You assume all legal and personal risk. No tool guarantees safety, anonymity, or access.
```

---

## 4. App Store Connect — step by step

### A. Accounts & IDs (before Archive)

1. Apple Developer Program → Certificates, Identifiers & Profiles.
2. Create App IDs:
   - `com.goldmannllc.IranVPN`
   - `com.goldmannllc.IranVPN.tunnel`
   - `com.goldmannllc.IranVPN.tunnel.xray`
3. Enable **Network Extensions → Packet Tunnel** on all three (requires Apple approval for distribution).
4. Request **Network Extension** entitlement approval if not already granted (App Store VPN apps need this). App Groups are optional (not required by the current client).
6. In Xcode: set **Team** (Goldmann LLC), fetch profiles, Archive → Distribute App → App Store Connect.

### B. Create the app record

1. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → **+**.
2. Platforms: iOS. Name: **Iran VPN**. Bundle ID: `com.goldmannllc.IranVPN`.
3. SKU: e.g. `iranvpn-ios-001`.

### C. App Information

| Field | Value |
|-------|-------|
| Name | Iran VPN |
| Subtitle | One-tap secure access |
| Category | Utilities *(primary)* / Productivity *(secondary)* |
| Content Rights | Confirm you own icon/branding rights |
| Age Rating | Complete questionnaire (VPN typically 4+ / no restricted content) |
| Privacy Policy URL | `https://goldmannllc.com/privacy` |

### D. Pricing & Availability

- Price: **Free**
- Availability: choose territories (consider excluding jurisdictions where publishing VPN apps creates legal issues for you)

### E. Version page (1.0)

1. Upload build from Organizer (or Transporter).
2. Paste **Description**, **Keywords**, **What’s New** from §1–3.
3. **Support URL:** `https://goldmannllc.com/contact`
4. **Marketing URL:** `https://goldmannllc.com/websites/iranvpn`
5. Screenshots: 6.7" and 6.1" (and iPad if you support iPad).
6. App Privacy (nutrition labels): match `PrivacyInfo.xcprivacy` + real collection (likely minimal / no tracking).
7. Export compliance: `ITSAppUsesNonExemptEncryption = YES` → answer encryption questions in ASC (VPN crypto).
8. Submit for Review. In Review Notes, mention:
   - Packet Tunnel NE entitlements
   - Demo: open app → accept disclaimer → Connect (needs network)
   - Contact: `support@goldmannllc.com`

### F. Pre-submit code checklist (iOS)

- [ ] `./scripts/fetch-ios-tunnel-deps.sh`
- [ ] Both appexes embedded and signed
- [ ] Device smoke-test: Psiphon connect + disconnect
- [ ] Privacy policy URL opens in Safari
- [ ] No debug-only Connected state

---

## 5. Google Play Console — step by step

### A. Signing

1. Create an upload keystore (not Android Debug).
2. Set env or `gradle.properties`:

```bash
export IRANVPN_KEYSTORE=/path/to/iranvpn-upload.jks
export IRANVPN_KEYSTORE_PASSWORD=...
export IRANVPN_KEY_ALIAS=...
export IRANVPN_KEY_PASSWORD=...
```

3. From `android/`:

```bash
./gradlew clean bundleRelease
```

4. Upload `app/build/outputs/bundle/release/app-release.aab`.

### B. Create the app

1. Play Console → Create app → name **Iran VPN**, default language English, Free, Declarations as required.
2. Application ID must match: `org.opensignalfoundation.iranvpn`.

### C. Store listing

| Field | Value |
|-------|-------|
| App name | Iran VPN |
| Short description | from §3 |
| Full description | from §3 |
| App icon | 512×512 high-res |
| Feature graphic | 1024×500 |
| Phone screenshots | ≥2 |
| Category | Tools / Productivity |
| Contact email | `support@goldmannllc.com` |
| Privacy policy | `https://goldmannllc.com/privacy` |
| Website | `https://goldmannllc.com/websites/iranvpn` |

### D. Policy / declarations (required for VPN)

1. **App content → Privacy policy** — paste `https://goldmannllc.com/privacy`.
2. **Data safety** — declare data collected (often little beyond crash/diagnostics if any); no sale of data.
3. **VPN app** questionnaire — complete honestly.
4. **Foreground service** → `specialUse` justification: VPN tunnel / connectivity.
5. **Ads:** No (unless you add them later).
6. **Target audience** / news apps / etc. — answer per actual content.

### E. Pre-submit code checklist (Android)

- [ ] Release AAB **not** signed with Debug (`apksigner verify --print-certs`)
- [ ] `POST_NOTIFICATIONS` runtime request on API 33+ (recommended)
- [ ] Device smoke-test: VpnService permission → Connected via Psiphon
- [ ] Privacy + safety URLs work offline of Play

---

## 6. Localization (optional but strong for Iran audience)

| Locale | Name | Subtitle / short |
|--------|------|------------------|
| **en-US** | Iran VPN | One-tap secure access |
| **fa** | ایران وی‌پی‌ان | اتصال امن با یک لمس |

Add Farsi screenshots if you localize the UI.

---

## 7. Review positioning (keep consistent)

Frame the listing like [Iran VPN on Goldmann LLC](https://goldmannllc.com/websites/iranvpn):

- Censorship-resistant networking research / digital safety  
- Publisher: Goldmann LLC  
- No guarantee of anonymity or access  
- No operational “bypass playbook” in store text  
- Point reviewers to `goldmannllc.com/privacy` + support contact  

---

## 8. Quick link cheat sheet (Goldmann LLC)

```
Company:   https://goldmannllc.com
Product:   https://goldmannllc.com/websites/iranvpn
Privacy:   https://goldmannllc.com/privacy
Terms:     https://goldmannllc.com/terms
Support:   https://goldmannllc.com/contact
GitHub:    https://github.com/bgoldmann/iranvpn

Support@:  support@goldmannllc.com
Privacy@:  privacy@goldmannllc.com
Legal@:    legal@goldmannllc.com
Security@: security@goldmannllc.com
Phone:     +1 (949) 264-2004
```

Optional research cite: https://www.opensignalfoundation.org/projects/iranvpn

---

## 9. Still blocking upload (from readiness audit)

Complete these before expecting approval:

1. Privacy Policy URL in both consoles: `https://goldmannllc.com/privacy`.  
2. Play: upload-keystore-signed AAB (not Debug).  
3. Apple: Network Extension distribution approval + Team signing + Archive.  
4. Device smoke-test both platforms.  
5. Play: VPN + FGS special-use + Data safety forms.  
6. Consider adding an explicit “Iran VPN app” privacy section on goldmannllc.com (current policy is site/services-general; App Review sometimes asks for app-specific data practices).
