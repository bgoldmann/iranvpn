#!/usr/bin/env bash
# Publish server list to primary and mirror (FR-8).
# Set env vars: S3_BUCKET, S3_PREFIX, MIRROR_URL, MIRROR_AUTH (optional)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_JSON="${1:-$SCRIPT_DIR/server-list.json}"
if [ ! -f "$CONFIG_JSON" ]; then
  echo "Usage: $0 [server-list.json]"
  echo "Create server-list.json with paths and sources, then run this script."
  echo "Example: cp server-list.json.example server-list.json && ./publish.sh"
  exit 1
fi

echo "Publishing $CONFIG_JSON..."

# Primary: S3 (optional)
if [ -n "$S3_BUCKET" ]; then
  PREFIX="${S3_PREFIX:-config}"
  if command -v aws &>/dev/null; then
    aws s3 cp "$CONFIG_JSON" "s3://${S3_BUCKET}/${PREFIX}/server-list.json" --acl public-read
    echo "  Uploaded to s3://${S3_BUCKET}/${PREFIX}/server-list.json"
  else
    echo "  Skipping S3 (aws CLI not found or S3_BUCKET not set)"
  fi
else
  echo "  Skipping S3 (set S3_BUCKET to enable)"
fi

# Mirror: HTTP PUT (optional)
if [ -n "$MIRROR_URL" ]; then
  if command -v curl &>/dev/null; then
    CURL_OPTS=(-X PUT -d "@$CONFIG_JSON" "$MIRROR_URL" -H "Content-Type: application/json")
    [ -n "$MIRROR_AUTH" ] && CURL_OPTS+=(-H "Authorization: $MIRROR_AUTH")
    if curl -sf "${CURL_OPTS[@]}"; then
      echo "  Uploaded to mirror: $MIRROR_URL"
    else
      echo "  Mirror upload failed (check MIRROR_URL and MIRROR_AUTH)"
      exit 1
    fi
  fi
else
  echo "  Skipping mirror (set MIRROR_URL to enable)"
fi

# GitHub: commit to repo (manual or via gh CLI)
echo ""
echo "For GitHub raw URL, commit server-list.json to your repo and ensure:"
echo "  https://raw.githubusercontent.com/OWNER/REPO/main/dist-config/server-list.json"
echo "  is publicly accessible."
echo ""
echo "Done. Config sources for clients:"
echo "  1. Primary: \${S3_URL:-https://\${S3_BUCKET}.s3.amazonaws.com/\${PREFIX}/server-list.json}"
echo "  2. Mirror: \$MIRROR_URL"
echo "  3. GitHub: https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json"
