#!/usr/bin/env bash
# Apply the 12 factory blueprints to Port, in dependency order.
# Idempotent: PUTs over an existing blueprint of the same identifier.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a

: "${PORT_CLIENT_ID:?set PORT_CLIENT_ID in .env}"
: "${PORT_CLIENT_SECRET:?set PORT_CLIENT_SECRET in .env}"
REGION="${REGION:-us}"
API=$([[ "$REGION" == "eu" ]] && echo "https://api.getport.io/v1" || echo "https://api.us.getport.io/v1")

echo "==> Authenticating against $API"
TOKEN=$(curl -sf -X POST "$API/auth/access_token" \
  -H 'Content-Type: application/json' \
  -d "{\"clientId\":\"$PORT_CLIENT_ID\",\"clientSecret\":\"$PORT_CLIENT_SECRET\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])')

# Dependency order: a relation's target blueprint must already exist.
ORDER=(goal service technical_decision risk brief plan data_source
       build_run verification heal_event release agent_invocation)

for id in "${ORDER[@]}"; do
  f="port/blueprints/$id.json"
  code=$(curl -s -o /tmp/port-bp.out -w '%{http_code}' -X POST "$API/blueprints" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary "@$f")
  if [[ "$code" == "409" ]]; then
    code=$(curl -s -o /tmp/port-bp.out -w '%{http_code}' -X PUT "$API/blueprints/$id" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary "@$f")
    echo "  ~ $id updated ($code)"
  elif [[ "$code" =~ ^2 ]]; then
    echo "  + $id created"
  else
    echo "  ! $id FAILED ($code)"; cat /tmp/port-bp.out; echo
  fi
done
echo "==> Done. Verify: https://app.getport.io -> Builder"
