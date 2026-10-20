#!/usr/bin/env bash
# Enable Network Extensions (Packet Tunnel) on IranVPN App IDs via App Store Connect API.
#
# Requires:
#   ASC_KEY_ID      (default: QL7L5YZ736 from Desktop AuthKey)
#   ASC_ISSUER_ID   (from developer.apple.com → Users and Access → Integrations → App Store Connect API)
#   ASC_KEY_PATH    (default: ~/Desktop/AuthKey_${ASC_KEY_ID}.p8)
#
# Usage:
#   export ASC_ISSUER_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
#   ./scripts/enable-packet-tunnel-asc.sh

set -euo pipefail

ASC_KEY_ID="${ASC_KEY_ID:-QL7L5YZ736}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/Desktop/AuthKey_${ASC_KEY_ID}.p8}"
# Issuer ID is NOT inside the .p8 — it’s the UUID on the App Store Connect API Keys page.
ASC_ISSUER_ID="${ASC_ISSUER_ID:-${APP_STORE_CONNECT_ISSUER_ID:-}}"

BUNDLE_IDS=(
  "com.goldmannllc.IranVPN"
  "com.goldmannllc.IranVPN.tunnel"
  "com.goldmannllc.IranVPN.tunnel.xray"
)

if [[ -z "$ASC_ISSUER_ID" ]]; then
  echo "Found key: $ASC_KEY_PATH (Key ID $ASC_KEY_ID)"
  echo "Still need Issuer ID (UUID on the same page as the key)."
  echo "Open: https://appstoreconnect.apple.com/access/integrations/api"
  echo "Then:  export ASC_ISSUER_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
  echo "       $0"
  exit 1
fi

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "Missing API key file: $ASC_KEY_PATH"
  exit 1
fi

python3 - "$ASC_ISSUER_ID" "$ASC_KEY_ID" "$ASC_KEY_PATH" "${BUNDLE_IDS[@]}" <<'PY'
import base64, json, sys, time, urllib.request

issuer, key_id, key_path, *bundles = sys.argv[1:]
with open(key_path) as f:
    private_key_pem = f.read()

try:
    import jwt  # PyJWT
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "PyJWT", "cryptography", "-q"])
    import jwt

now = int(time.time())
token = jwt.encode(
    {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
    private_key_pem,
    algorithm="ES256",
    headers={"kid": key_id},
)
if isinstance(token, bytes):
    token = token.decode()

def api(method, path, body=None):
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}",
        data=None if body is None else json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        return e.code, json.loads(err) if err.startswith("{") else {"raw": err}

# List bundle IDs
status, data = api("GET", "/v1/bundleIds?limit=200")
if status != 200:
    print("Failed to list bundleIds:", status, data)
    sys.exit(1)

by_id = {b["attributes"]["identifier"]: b for b in data.get("data", [])}

for bid in bundles:
    row = by_id.get(bid)
    if not row:
        print(f"CREATE {bid}")
        status, created = api("POST", "/v1/bundleIds", {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": bid,
                    "name": bid.replace(".", " "),
                    "platform": "IOS",
                },
            }
        })
        if status not in (200, 201):
            print(f"  failed create: {status} {created}")
            continue
        row = created["data"]
        print(f"  created id={row['id']}")
    else:
        print(f"FOUND {bid} id={row['id']}")

    # Enable NETWORK_EXTENSIONS capability
    status, caps = api("GET", f"/v1/bundleIds/{row['id']}/bundleIdCapabilities")
    existing = []
    if status == 200:
        existing = [c["attributes"]["capabilityType"] for c in caps.get("data", [])]
    if "NETWORK_EXTENSIONS" in existing:
        print("  NETWORK_EXTENSIONS already enabled")
        continue

    status, result = api("POST", "/v1/bundleIdCapabilities", {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "NETWORK_EXTENSIONS"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": row["id"]}}
            },
        }
    })
    if status in (200, 201):
        print("  enabled NETWORK_EXTENSIONS")
    else:
        print(f"  enable failed: {status} {result}")

print("Done. Clean rebuild in Xcode with IRANVPN_ENTITLEMENTS_SUFFIX=-NetworkExtension.")
PY
