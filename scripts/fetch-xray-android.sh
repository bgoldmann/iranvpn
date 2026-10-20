#!/usr/bin/env bash
# Download Xray-core Android binaries into app assets (optional; LibXray AAR preferred).
# Run from repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/android/app/src/main/assets/xray"
VERSION="${XRAY_VERSION:-25.9.11}"
BASE="https://github.com/XTLS/Xray-core/releases/download/v${VERSION}"

declare -A MAP=(
  [android-arm64-v8a]=arm64-v8a
  [android-arm32-v7a]=armeabi-v7a
  [android-amd64]=x86_64
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"
echo "Fetching Xray-core v${VERSION}…"

for arch in "${!MAP[@]}"; do
  abi="${MAP[$arch]}"
  zip="Xray-android-${arch#android-}.zip"
  # Release asset naming varies; try common patterns
  for candidate in \
    "Xray-android-${abi}.zip" \
    "Xray-${arch}.zip" \
    "Xray-linux-arm64-v8a.zip"
  do
    url="${BASE}/${candidate}"
    if curl -fsSIL "$url" >/dev/null 2>&1; then
      echo "  $abi ← $candidate"
      curl -fsSL "$url" -o "${TMP}/x.zip"
      unzip -qo "${TMP}/x.zip" -d "${TMP}/${abi}"
      bin="$(find "${TMP}/${abi}" -type f \( -name xray -o -name Xray \) | head -1)"
      if [[ -n "$bin" ]]; then
        mkdir -p "${DEST}/${abi}"
        cp "$bin" "${DEST}/${abi}/xray"
        chmod +x "${DEST}/${abi}/xray"
      fi
      break
    fi
  done
done

if ! ls "${DEST}"/*/xray >/dev/null 2>&1; then
  echo "WARN: No Xray Android zip matched for v${VERSION}."
  echo "Prefer LibXray AAR, or set XRAY_VERSION / download manually into assets/xray/<abi>/xray"
  exit 0
fi
echo "Done. Binaries in ${DEST}/<abi>/xray"
