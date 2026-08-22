#!/usr/bin/env bash
# Apply the 12 factory blueprints to Port, in dependency order.
# Idempotent: PUTs over an existing blueprint of the same identifier.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a

: "${PORT_CLIENT_ID:?set PORT_CLIENT_ID in .env}"
: "${PORT_CLIENT_SECRET:?set PORT_CLIENT_SECRET in .env}"
# Region auto-detection. Both api.port.io (EU) and api.us.port.io (US) are live and
# answer identically to anonymous probes, so the ONLY reliable way to tell which region
# an org lives in is to try the token exchange: the wrong region rejects the credentials.
# $REGION, if set, is tried first; otherwise we try both and use whichever authenticates.
auth_at() {
  curl -sf -X POST "$1/auth/access_token" \
    -H 'Content-Type: application/json' \
    -d "{\"clientId\":\"$PORT_CLIENT_ID\",\"clientSecret\":\"$PORT_CLIENT_SECRET\"}" \
    2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])' 2>/dev/null
}

case "${REGION:-}" in
  eu) CANDIDATES=("https://api.port.io/v1" "https://api.us.port.io/v1") ;;
  us) CANDIDATES=("https://api.us.port.io/v1" "https://api.port.io/v1") ;;
  *)  CANDIDATES=("https://api.port.io/v1" "https://api.us.port.io/v1") ;;
esac

API=""; TOKEN=""
for c in "${CANDIDATES[@]}"; do
  echo "==> Trying $c"
  t=$(auth_at "$c") || true
  if [[ -n "$t" ]]; then API="$c"; TOKEN="$t"; break; fi
  echo "    rejected (wrong region or bad credentials)"
done

if [[ -z "$TOKEN" ]]; then
  echo "!! Could not authenticate against either region."
  echo "   Check PORT_CLIENT_ID / PORT_CLIENT_SECRET in .env."
  exit 1
fi

DETECTED=$([[ "$API" == *"api.us."* ]] && echo us || echo eu)
echo "==> Authenticated. Region is '$DETECTED' ($API)"
if [[ -n "${REGION:-}" && "$REGION" != "$DETECTED" ]]; then
  echo "!! WARNING: .env says REGION=$REGION but your org is actually '$DETECTED'."
  echo "   Fix .env, and point .mcp.json at $([[ $DETECTED == us ]] && echo https://mcp.us.port.io/v1 || echo https://mcp.port.io/v1)"
fi

# Dependency order: a relation's target blueprint must already exist.
ORDER=(goal factory_service technical_decision risk brief plan data_source
       build_run verification heal_event release agent_invocation)

for id in "${ORDER[@]}"; do
  f="port/blueprints/$id.json"
  code=$(curl -s -o /tmp/port-bp.out -w '%{http_code}' -X POST "$API/blueprints" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary "@$f")
  if [[ "$code" == "409" && "${PORT_ALLOW_OVERWRITE:-0}" != "1" ]]; then
    echo "  ! $id already exists and is NOT ours to reshape — skipping."
    echo "    A PUT here would strip its schema and break any scorecard bound to it."
    echo "    Re-run with PORT_ALLOW_OVERWRITE=1 if you really mean to overwrite."
    continue
  elif [[ "$code" == "409" ]]; then
    code=$(curl -s -o /tmp/port-bp.out -w '%{http_code}' -X PUT "$API/blueprints/$id" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary "@$f")
    echo "  ~ $id updated ($code)"
  elif [[ "$code" =~ ^2 ]]; then
    echo "  + $id created"
  else
    echo "  ! $id FAILED ($code)"; cat /tmp/port-bp.out; echo
  fi
done
echo "==> Done. Verify: https://app$([[ $DETECTED == us ]] && echo .us).port.io -> Builder"
