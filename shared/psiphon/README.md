# Shared Psiphon bootstrap

Canonical research bootstrap used by **iOS**, **macOS**, **Android**, and **Windows**.

| File | Role |
|------|------|
| `psiphon-config.json` | Propagation/Sponsor IDs + tunnel timeouts |
| `psiphon-embedded-server-entries.txt` | Hex-encoded server entries (`startTunneling` / bundle) |

Sync into each app:

```bash
./scripts/sync-psiphon-bootstrap.sh
```

Optional fuller extract (gitignored): `psiphon-embedded-server-entries.local.txt` next to the platform resources.

Values come from the public Shiro Khorshid APK. For production distributor keys (`RemoteServerListURLs`, signature public key), see `docs/psiphon-integration.md`.
