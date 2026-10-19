# Iran VPN — Windows

Windows client using `core` as a native lib. Path race + SOCKS probe; system-wide TUN is **not** claimed until tun2socks/hev-socks5 is bundled.

## Stack

- **Rust** app with egui UI; links to `iran-vpn-core`.
- **Local SOCKS:** Psiphon / Xray on PATH; Connect succeeds only after a SOCKS probe.
- **Wintun:** code exists but is **not** started on Connect — a drop-only TUN would blackhole the OS.

## Build

```bash
cd windows
cargo build --release
```

Requires: Rust, Windows SDK. Wintun DLL is fetched automatically by the `wintun` crate (unused until forwarding ships).

## Run

```bash
cargo run -p iran-vpn-windows --release
```

Place `psiphon-tunnel-core` and/or `xray` on PATH. Connect tries Psiphon (then Xray if present), probes via SOCKS, and reports **Local SOCKS ready** — not a system VPN.

**Demo (no binaries):** `IRAN_VPN_DEMO=1 cargo run -p iran-vpn-windows --release`

UI connect is non-blocking. Advanced panel accepts full Xray JSON (not bare share links).

## Distribution

US-005: GitHub Releases + mirror. See [docs/distribution.md](../docs/distribution.md).
