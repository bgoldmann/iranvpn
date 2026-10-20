# iOS / macOS providers (Conduit on hold)

Apple Network Extension rules force **one Go runtime per appex process**. That is why we already split:

| Appex | Bundle ID | Engine |
|-------|-----------|--------|
| `IranVPNTunnel` | `….tunnel` | Psiphon |
| `IranVPNTunnelXray` | `….tunnel.xray` | LibXray |

## What works today

| Provider | iOS | macOS |
|----------|-----|-------|
| **Psiphon** (zero-config) | Yes | Yes |
| **Conduit / in-proxy** | App + tunnel inject compartment; **waiting on Psiphon keys** | App + tunnel inject compartment; **waiting on Psiphon keys** |
| **Xray** VLESS / VMess / Trojan / Reality | Yes (import → Xray appex) | **Not yet** (no second appex) |
| **Outline `ss://`** | Yes via LibXray shadowsocks | Not yet (needs Xray appex) |
| **sing-box / Hysteria2 `hy2://`** | No (needs Libbox / 3rd appex) | No |
| **Tor / Snowflake** | No embedded; use Onion Browser separately | No embedded; system Tor SOCKS possible later |
| **AmneziaWG** | No | No |

## Why Tor / sing-box are harder on Apple

- **Tor:** Orbot is Android-only. Embedding `tor` inside a Packet Tunnel is large, review-sensitive, and still needs bridges. Practical UX = “Open Onion Browser” CTA, not in-app race.
- **sing-box:** Official Apple builds exist (SFI/SFM), but that is another Go stack → **third** NE target (`….tunnel.singbox`), App ID + Packet Tunnel entitlement, and store review complexity. Android already races sing-box as a subprocess; iOS cannot shell out the same way inside the NE sandbox as freely.

## Near-term plan

1. **Done:** iOS Advanced accepts **`ss://`** (Outline) through existing Xray appex.  
2. **Next:** macOS **IranVPNTunnelXray** parity with iOS (same LibXray + ShareLinkParser, including `ss://`).  
3. **Later:** optional Libbox appex for Hy2 / multi-protocol; Tor = deep-link only.  
4. **Conduit:** resume when `sponsor@psiphon.ca` replies.

## User guidance

- **iOS:** Connect = Psiphon; Advanced import `vless://` / `ss://` for Xray path.  
- **macOS:** Connect = Psiphon only until Xray appex ships; use Android/Windows for Outline/Hy2 meanwhile.  
- **Android:** Full race (Psiphon → Xray → sing-box → Tor → Outline) after `./scripts/fetch-sing-box-android.sh`.
