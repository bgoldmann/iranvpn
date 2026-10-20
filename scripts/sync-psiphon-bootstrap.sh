#!/usr/bin/env bash
# Sync shared/psiphon bootstrap into iOS, macOS, Android, and Windows clients.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/shared/psiphon"
CFG="${SRC}/psiphon-config.json"
ENTRIES="${SRC}/psiphon-embedded-server-entries.txt"

if [[ ! -f "$CFG" || ! -f "$ENTRIES" ]]; then
  echo "Missing $CFG or $ENTRIES — extract from Shiro APK first (see docs/psiphon-integration.md)." >&2
  exit 1
fi

copy_pair() {
  local dest="$1"
  mkdir -p "$dest"
  cp "$CFG" "$dest/psiphon-config.json"
  cp "$ENTRIES" "$dest/psiphon-embedded-server-entries.txt"
  echo "Updated $dest"
}

copy_pair "${ROOT}/ios/IranVPNTunnel/Resources"
copy_pair "${ROOT}/macos/IranVPNTunnel/Resources"
copy_pair "${ROOT}/android/app/src/main/assets/psiphon"

# Windows CLI config: fixed SOCKS 1080 + TargetServerEntry (first bootstrap line)
mkdir -p "${ROOT}/windows/psiphon"
cp "$ENTRIES" "${ROOT}/windows/psiphon/psiphon-embedded-server-entries.txt"
export IRANVPN_ROOT="$ROOT"
python3 <<'PY'
import json, os
from pathlib import Path
root = Path(os.environ["IRANVPN_ROOT"])
cfg = json.loads((root / "shared/psiphon/psiphon-config.json").read_text())
first = (root / "shared/psiphon/psiphon-embedded-server-entries.txt").read_text().strip().splitlines()[0]
cfg["LocalSocksProxyPort"] = 1080
cfg["LocalHttpProxyPort"] = 0
cfg["TargetServerEntry"] = first
cfg["EmitDiagnosticNotices"] = True
out = root / "windows/psiphon/psiphon.config"
out.write_text(json.dumps(cfg, indent=2) + "\n")
print(f"Updated {out}")
PY

echo "Done."
