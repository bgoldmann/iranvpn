#!/usr/bin/env bash
# Thin launcher: open Conduit download / install page, or start a local Conduit binary if present.
set -euo pipefail

CONDUIT_URL="${CONDUIT_URL:-https://conduit.psiphon.ca/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

find_binary() {
  for c in conduit Conduit "Psiphon Conduit" \
    "$SCRIPT_DIR/bin/conduit" \
    "$HOME/Applications/Conduit.app" \
    "/Applications/Conduit.app"; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
    if [[ -d "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

if BIN=$(find_binary); then
  echo "Starting Conduit: $BIN"
  if [[ "$BIN" == *.app ]]; then
    open "$BIN"
  else
    exec "$BIN" "$@"
  fi
else
  echo "Conduit not found locally."
  echo "Opening download page: $CONDUIT_URL"
  if command -v open >/dev/null 2>&1; then
    open "$CONDUIT_URL"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$CONDUIT_URL"
  else
    echo "Visit: $CONDUIT_URL"
  fi
fi
