#!/usr/bin/env bash
# Publish server list to primary and mirrors (FR-8).
# Optional env:
#   S3_BUCKET, S3_PREFIX, MIRROR_URL, MIRROR_AUTH
#   CF_R2=1  — upload to Cloudflare R2 via wrangler (see docs/cloudflare-config-mirror.md)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_JSON="${1:-$SCRIPT_DIR/server-list.json}"
if [ ! -f "$CONFIG_JSON" ]; then
  echo "Usage: $0 [server-list.json]"
  echo "Create server-list.json with paths and sources, then run this script."
  echo "Example: cp server-list.json.example server-list.json && ./publish.sh"
  exit 1
fi
# Absolute path so `cd` into the Worker dir does not break --file.
CONFIG_JSON="$(cd "$(dirname "$CONFIG_JSON")" && pwd)/$(basename "$CONFIG_JSON")"

echo "Publishing $CONFIG_JSON..."

# Primary: S3 (optional)
if [ -n "$S3_BUCKET" ]; then
  PREFIX="${S3_PREFIX:-config}"
  if command -v aws &>/dev/null; then
    aws s3 cp "$CONFIG_JSON" "s3://${S3_BUCKET}/${PREFIX}/server-list.json" --acl public-read
    echo "  Uploaded to s3://${S3_BUCKET}/${PREFIX}/server-list.json"
  else
    echo "  S3_BUCKET is set but aws CLI was not found" >&2
    exit 1
  fi
else
  echo "  Skipping S3 (set S3_BUCKET to enable)"
fi

# Cloudflare R2 (optional) — Worker serves this when CONFIG_BUCKET is bound
if [ "${CF_R2:-}" = "1" ] || [ "${CF_R2:-}" = "true" ]; then
  CF_DIR="$ROOT_DIR/cloudflare/config-mirror"
  if command -v npx &>/dev/null; then
    (cd "$CF_DIR" && npx wrangler r2 object put iranvpn-config/server-list.json --file="$CONFIG_JSON")
    echo "  Uploaded to R2: iranvpn-config/server-list.json"
    echo "  R2 is served only after [[r2_buckets]] is uncommented in cloudflare/config-mirror/wrangler.toml and the Worker is redeployed."
  else
    echo "  CF_R2 is set but npx was not found" >&2
    exit 1
  fi
else
  echo "  Skipping Cloudflare R2 (set CF_R2=1 to enable)"
fi

# Mirror: HTTP PUT (optional)
if [ -n "$MIRROR_URL" ]; then
  if command -v curl &>/dev/null; then
    CURL_OPTS=(-X PUT -d "@$CONFIG_JSON" "$MIRROR_URL" -H "Content-Type: application/json")
    [ -n "$MIRROR_AUTH" ] && CURL_OPTS+=(-H "Authorization: $MIRROR_AUTH")
    if curl -sf "${CURL_OPTS[@]}"; then
      echo "  Uploaded to mirror: $MIRROR_URL"
    else
      echo "  Mirror upload failed (check MIRROR_URL and MIRROR_AUTH)" >&2
      exit 1
    fi
  else
    echo "  MIRROR_URL is set but curl was not found" >&2
    exit 1
  fi
else
  echo "  Skipping mirror (set MIRROR_URL to enable)"
fi

# GitHub: commit to repo (manual or via gh CLI)
echo ""
echo "For GitHub raw URL, commit server-list.json to your repo and ensure:"
echo "  https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json"
echo "  is publicly accessible."
echo ""
echo "Done. Config sources for clients (order):"
echo "  1. Cloudflare: https://iranvpn-config.goldmannllc.com/server-list.json"
echo "  2. GitHub:     https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json"
echo "  3. jsDelivr:   https://cdn.jsdelivr.net/gh/bgoldmann/iranvpn@main/dist-config/server-list.json"
echo ""
echo "Deploy Worker: cd cloudflare/config-mirror && npx wrangler deploy"
echo "Docs: docs/cloudflare-config-mirror.md"
