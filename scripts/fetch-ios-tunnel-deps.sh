#!/usr/bin/env bash
# Fetch PsiphonTunnel + LibXray Apple frameworks into ios/Vendor/ (not committed — ~540MB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/ios/Vendor"
TMP="${TMPDIR:-/tmp}/iranvpn-ios-deps-$$"
mkdir -p "$VENDOR" "$TMP"
trap 'rm -rf "$TMP"' EXIT

PSIPHON_TAG="${PSIPHON_TAG:-v2.0.41}"
LIBXRAY_TAG="${LIBXRAY_TAG:-v26.10.17}"

echo "==> PsiphonTunnel ${PSIPHON_TAG}"
git clone --depth 1 --branch "$PSIPHON_TAG" \
  https://github.com/Psiphon-Labs/psiphon-tunnel-core-iOS-library.git \
  "$TMP/psiphon"
rm -rf "$VENDOR/PsiphonTunnel.xcframework"
cp -R "$TMP/psiphon/Frameworks/PsiphonTunnel.xcframework" "$VENDOR/"

echo "==> LibXray ${LIBXRAY_TAG}"
curl -fsSL -o "$TMP/libxray-apple-cgo.zip" \
  "https://github.com/XTLS/libXray/releases/download/${LIBXRAY_TAG}/libxray-apple-cgo.zip"
unzip -qo "$TMP/libxray-apple-cgo.zip" -d "$TMP"
rm -rf "$VENDOR/LibXray.xcframework"
cp -R "$TMP/libxray-apple-cgo/LibXray.xcframework" "$VENDOR/"

echo "OK:"
du -sh "$VENDOR"/*
echo
echo "Note: Psiphon and LibXray both embed a Go runtime — never link both into the same appex process."
echo "IranVPNTunnel links Psiphon; IranVPNTunnelXray links LibXray."
