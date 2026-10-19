# Iran VPN — Windows

Windows tunnel app using `core` as native lib. Tunnel via Wintun.

## Stack

- **Rust** app with egui UI; links to `iran-vpn-core`.
- **Wintun:** user-space TUN; establish tunnel and forward to path (Psiphon/Conduit/Xray/Rostam).

## Build

```bash
cd windows
cargo build --release
```

Requires: Rust, Windows SDK. Wintun DLL is fetched automatically by the `wintun` crate.

## Run

```bash
cargo run -p iran-vpn-windows --release
```

Place `psiphon-tunnel-core` and/or `xray` on PATH. Connect races paths, probes via SOCKS, then brings up Wintun.

**Demo (no binaries):** `IRAN_VPN_DEMO=1 cargo run -p iran-vpn-windows --release`

UI connect is non-blocking. Advanced panel accepts VLESS/VMess/Trojan share links.

## Distribution

US-005: GitHub Releases + mirror. See [docs/distribution.md](../docs/distribution.md).
