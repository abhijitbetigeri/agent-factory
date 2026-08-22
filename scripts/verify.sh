#!/usr/bin/env bash
# Pre-demo preflight. Run before you start building, and again before demoing.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0; warn=0
ok(){ echo "  ✅ $1"; pass=$((pass+1)); }
no(){ echo "  ❌ $1"; fail=$((fail+1)); }
wn(){ echo "  ⚠️  $1"; warn=$((warn+1)); }

echo "== toolchain =="
node -v >/dev/null 2>&1 && ok "node $(node -v)" || no "node missing"
[[ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" -ge 20 ]] && ok "node >= 20" || no "node < 20 (Bright Data CLI needs 20+)"

echo "== env =="
[[ -f "$R/.env" ]] && { set -a; . "$R/.env"; set +a; ok ".env present"; } || no ".env missing (cp .env.example .env)"
for v in PORT_CLIENT_ID PORT_CLIENT_SECRET BRIGHTDATA_API_KEY SIGNOZ_INGESTION_KEY; do
  [[ -n "${!v:-}" ]] && ok "$v set" || no "$v empty"
done
# Use-case-dependent: warn, don't fail, until the idea is chosen.
[[ -n "${SCRAPER_REAL_COLLECTOR_ID:-}" && "${SCRAPER_REAL_COLLECTOR_ID:-}" != \<* ]] \
  && ok "collector id set" || wn "collector id unset (blocked on use-case choice)"

echo "== port =="
# `claude mcp list` cannot run inside a Claude Code session, so read the config directly.
REPO_MCP="$R/.mcp.json" python3 - <<'PY' && ok "port MCP registered" || no "port MCP not registered (./scripts/setup-port-mcp.sh)"
import json,os,sys
found=False
import pathlib
ROOT=pathlib.Path(__file__).resolve().parent if '__file__' in dir() else pathlib.Path('.')
for p in (os.path.expanduser('~/.claude.json'), os.environ.get('REPO_MCP','')):
    try: d=json.load(open(p))
    except Exception: continue
    pools=[d.get('mcpServers') or {}]+[ (v or {}).get('mcpServers') or {} for v in (d.get('projects') or {}).values()]
    if any('port' in s for s in pools): found=True
sys.exit(0 if found else 1)
PY
n=$(ls "$R"/port/blueprints/*.json 2>/dev/null | wc -l | tr -d ' ')
python3 -c "
import json,glob,sys
for f in glob.glob('$R/port/blueprints/*.json'): json.load(open(f))
" 2>/dev/null && [[ "$n" == "12" ]] && ok "12 blueprints valid JSON" || no "blueprints missing/invalid (found $n)"

echo "== bright data =="
BD="npx --yes --package @brightdata/cli brightdata"
$BD --version >/dev/null 2>&1 && ok "CLI runs" || no "CLI failed"
if [[ -n "${SCRAPER_REAL_COLLECTOR_ID:-}" && "${SCRAPER_REAL_COLLECTOR_ID:-}" != \<* && -n "${SCRAPER_REAL_TARGET_URL:-}" ]]; then
  $BD scraper run "$SCRAPER_REAL_COLLECTOR_ID" "$SCRAPER_REAL_TARGET_URL" --sync --sync-timeout 50 >/tmp/bd.json 2>&1 \
    && ok "collector returns data" || no "collector run failed (see /tmp/bd.json)"
fi

echo "== signoz — all three signals =="
(cd "$R/otel-smoke" && node run.js >/dev/null 2>&1) && ok "otel smoke run (traces+metrics)" || no "otel smoke failed"
(cd "$R/otel-smoke" && node -e "
const {log}=require('./tracing.js'); const {trace}=require('@opentelemetry/api');
trace.getTracer('t').startActiveSpan('preflight',s=>{log('info','preflight log record',{check:1});s.end();});
setTimeout(()=>process.exit(0),600);
" 2>&1 | grep -q traceId) && ok "logs signal emits, trace-correlated" || no "logs signal broken"

echo; echo "$pass passed, $fail failed, $warn warned"
[[ $fail -eq 0 ]]
