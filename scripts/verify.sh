#!/usr/bin/env bash
# Pre-demo preflight. Run this before you start building, and again before demoing.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok(){ echo "  ✅ $1"; pass=$((pass+1)); }
no(){ echo "  ❌ $1"; fail=$((fail+1)); }

echo "== toolchain =="
node -v >/dev/null 2>&1 && ok "node $(node -v)" || no "node missing"
[[ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -ge 20 ]] && ok "node >= 20" || no "node < 20 (Bright Data CLI needs 20+)"

echo "== env =="
[[ -f "$R/.env" ]] && { set -a; . "$R/.env"; set +a; ok ".env present"; } || no ".env missing (cp .env.example .env)"
for v in BRIGHTDATA_API_KEY SCRAPER_STUDIO_COLLECTOR_ID SIGNOZ_INGESTION_KEY; do
  [[ -n "${!v:-}" ]] && ok "$v set" || no "$v empty"
done

echo "== bright data =="
BD="npx --yes --package @brightdata/cli brightdata"
$BD --version >/dev/null 2>&1 && ok "CLI runs" || no "CLI failed"
if [[ -n "${SCRAPER_STUDIO_COLLECTOR_ID:-}" && -n "${SCRAPER_TARGET_URL:-}" ]]; then
  $BD scraper run "$SCRAPER_STUDIO_COLLECTOR_ID" "$SCRAPER_TARGET_URL" --sync --sync-timeout 50 >/tmp/bd.json 2>&1 \
    && ok "collector returns data" || no "collector run failed (see /tmp/bd.json)"
fi

echo "== port mcp =="
claude mcp list 2>/dev/null | grep -qi port && ok "port MCP registered" || no "port MCP not registered"

echo "== signoz =="
(cd "$R/otel-smoke" && node run.js >/dev/null 2>&1) && ok "otel smoke run" || no "otel smoke failed"

echo; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
