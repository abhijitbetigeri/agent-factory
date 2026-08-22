#!/usr/bin/env bash
# Import the factory dashboard into self-hosted SigNoz.
#
# SigNoz has no API key for self-hosted installs — dashboard creation needs a JWT from
# an interactive login. This prompts for your credentials and uses them locally; nothing
# is written to disk or into any file the repo tracks.
set -euo pipefail
cd "$(dirname "$0")/.."
SIGNOZ="${SIGNOZ_URL:-http://localhost:8080}"
DASH=signoz/dashboard-factory-health.json

read -r -p "SigNoz email: " EMAIL
read -r -s -p "SigNoz password: " PASS; echo

TOKEN=$(curl -sf -X POST "$SIGNOZ/api/v1/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessJwt"])') || {
    echo "!! login failed — check the email/password you registered at $SIGNOZ"; exit 1; }
unset PASS

code=$(curl -s -o /tmp/signoz-dash.out -w '%{http_code}' -X POST "$SIGNOZ/api/v1/dashboards" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data-binary "@$DASH")

if [[ "$code" =~ ^2 ]]; then
  uuid=$(python3 -c 'import json;d=json.load(open("/tmp/signoz-dash.out"));print(d.get("data",{}).get("uuid") or d.get("uuid",""))' 2>/dev/null || true)
  echo "==> imported. $SIGNOZ/dashboard/${uuid}"
else
  echo "!! import failed ($code)"; cat /tmp/signoz-dash.out; echo
  echo "   Fallback: $SIGNOZ -> Dashboards -> New dashboard -> Import JSON -> paste $DASH"
fi
