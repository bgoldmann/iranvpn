# Psiphon tunnel resources

Loaded by `PsiphonTunnelController` (same pattern as Psiphon’s TunneledWebRequest sample).

| File | Role |
|------|------|
| `psiphon-config.json` | `getPsiphonConfig` — Propagation/Sponsor IDs + optional remote list keys |
| `psiphon-config.local.json` | Optional override (gitignored) merged on top for distributor secrets |
| `psiphon-embedded-server-entries.txt` | Bootstrap server entries from Psiphon Inc. |

Bundled `PropagationChannelId` / `SponsorId` and `psiphon-embedded-server-entries.txt` are extracted from the public Shiro Khorshid APK (research bootstrap). Optional gitignored `psiphon-embedded-server-entries.local.txt` can hold a fuller extract. For production / Iran-grade circumvention, obtain `RemoteServerListURLs` + `RemoteServerListSignaturePublicKey` from Psiphon Inc. (see `docs/psiphon-integration.md`).
