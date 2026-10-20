#!/usr/bin/env bash
# Download official sing-box Android CLI binaries into app assets.
# Enables Outline (ss://), Hysteria2, and sing-box JSON paths on Android.
# Run from repo root. GPL-3.0 — https://github.com/SagerNet/sing-box
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/android/app/src/main/assets/sing-box"
VERSION="${SING_BOX_VERSION:-1.14.3}"
BASE="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"
echo "Fetching sing-box v${VERSION} for Android…"

# archive_suffix abi
while read -r arch abi; do
  [[ -z "$arch" || "$arch" =~ ^# ]] && continue
  archive="sing-box-${VERSION}-${arch}.tar.gz"
  url="${BASE}/${archive}"
  echo "  $abi ← $archive"
  curl -fsSL "$url" -o "${TMP}/${archive}"
  mkdir -p "${TMP}/${abi}"
  tar -xzf "${TMP}/${archive}" -C "${TMP}/${abi}"
  bin="$(find "${TMP}/${abi}" -type f -name sing-box | head -1)"
  if [[ -z "$bin" ]]; then
    echo "ERROR: sing-box binary not found in $archive" >&2
    exit 1
  fi
  mkdir -p "${DEST}/${abi}"
  cp "$bin" "${DEST}/${abi}/sing-box"
  chmod +x "${DEST}/${abi}/sing-box"
done <<'EOF'
android-arm64 arm64-v8a
android-arm armeabi-v7a
android-amd64 x86_64
android-386 x86
EOF

if [[ -f "${DEST}/arm64-v8a/sing-box" ]]; then
  cp "${DEST}/arm64-v8a/sing-box" "${DEST}/sing-box"
fi

echo "Done. Binaries in ${DEST}/<abi>/sing-box"
ls -la "${DEST}"/*/sing-box

# Gitignore tip: binaries are large — commit is optional; CI can fetch.
echo "Tip: add android/app/src/main/assets/sing-box/ to .gitignore if you prefer not to commit ~100MB."
