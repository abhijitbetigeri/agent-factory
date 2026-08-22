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
for v in PORT_CLIENT_ID PORT_CLIENT_SECRET BRIGHTDATA_API_KEY; do
  [[ -n "${!v:-}" ]] && ok "$v set" || no "$v empty"
done
# SigNoz: cloud needs a key, self-hosted needs an endpoint. Either satisfies this.
if [[ -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]]; then
  ok "SigNoz self-hosted ($OTEL_EXPORTER_OTLP_ENDPOINT)"
elif [[ -n "${SIGNOZ_INGESTION_KEY:-}" ]]; then
  ok "SigNoz cloud (ingestion key set)"
else
  no "SigNoz unconfigured — set OTEL_EXPORTER_OTLP_ENDPOINT (self-hosted) or SIGNOZ_INGESTION_KEY (cloud)"
fi
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
# Count is derived, not hardcoded — adding a blueprint should not fail preflight.
# What matters is that every file parses and every relation target actually exists.
bp_msg=$(python3 - "$R" <<'PYBP'
import json,glob,sys,os
root=sys.argv[1]
files=glob.glob(os.path.join(root,'port/blueprints/*.json'))
if not files: print("no blueprint files found"); sys.exit(1)
ids=set(); rels=[]
for f in files:
    try: b=json.load(open(f))
    except Exception as e: print(f"{os.path.basename(f)} is not valid JSON: {e}"); sys.exit(1)
    ids.add(b['identifier'])
    for name,r in (b.get('relations') or {}).items():
        rels.append((b['identifier'],name,r.get('target')))
# Port built-ins we deliberately point at are fine; only flag targets we neither
# define nor know to exist upstream.
known_external={'service','_team','_user'}
dangling=[f"{a}.{n} -> {t}" for a,n,t in rels if t not in ids and t not in known_external]
if dangling: print("dangling relation targets: "+", ".join(dangling)); sys.exit(1)
print(f"{len(ids)} blueprints valid, {len(rels)} relations resolve")
PYBP
) && ok "$bp_msg" || no "$bp_msg"

echo "== bright data =="
BD="npx --yes --package @brightdata/cli brightdata"
$BD --version >/dev/null 2>&1 && ok "CLI runs" || no "CLI failed"
# c_mirror is the LOAD-BEARING collector: it feeds the data contract that breaks,
# alerts and heals (CONTRACTS C3/C4). Check it strictly -- it returns well inside 50s.
if [[ -n "${SCRAPER_MIRROR_COLLECTOR_ID:-}" && -n "${SCRAPER_MIRROR_TARGET_URL:-}" ]]; then
  if $BD scraper run "$SCRAPER_MIRROR_COLLECTOR_ID" "$SCRAPER_MIRROR_TARGET_URL" \
       --sync --sync-timeout 50 --pretty >/tmp/bd-mirror.json 2>&1; then
    rate=$(node -e "
      process.env.SCRAPER_REQUIRED_FIELDS='${SCRAPER_REQUIRED_FIELDS:-name,price}';
      const s=require('$R/factory/supplier.js'), fs=require('fs');
      const t=fs.readFileSync('/tmp/bd-mirror.json','utf8');
      console.log(s.nullRate(JSON.parse(t.slice(t.indexOf('[')))).rate);
    " 2>/dev/null)
    if [[ -n "$rate" ]] && node -e "process.exit(${rate:-1} <= ${SCRAPER_NULL_RATE_THRESHOLD:-0.05} ?0:1)"; then
      ok "c_mirror data contract holds (null rate $rate)"
    else
      no "c_mirror null rate $rate exceeds ${SCRAPER_NULL_RATE_THRESHOLD:-0.05} — mirror may still be broken (./scripts/break-mirror.sh --reset)"
    fi
  else
    no "c_mirror run failed (see /tmp/bd-mirror.json)"
  fi
fi

# c_real is triage-only and routinely exceeds the CLI's 50s sync cap (50 is the max
# allowed), so --sync failed a perfectly working collector. Poll instead, and only
# WARN on slowness -- a slow triage collector must not fail the whole preflight.
if [[ -n "${SCRAPER_REAL_COLLECTOR_ID:-}" && "${SCRAPER_REAL_COLLECTOR_ID:-}" != \<* && -n "${SCRAPER_REAL_TARGET_URL:-}" ]]; then
  $BD scraper run "$SCRAPER_REAL_COLLECTOR_ID" "$SCRAPER_REAL_TARGET_URL" --pretty >/tmp/bd.json 2>&1 &
  bdpid=$!
  for _ in $(seq 1 60); do kill -0 $bdpid 2>/dev/null || break; sleep 2; done
  if kill -0 $bdpid 2>/dev/null; then
    kill $bdpid 2>/dev/null; wait $bdpid 2>/dev/null
    wn "c_real slower than 120s (triage only, not load-bearing)"
  elif wait $bdpid && grep -q '"components"' /tmp/bd.json; then
    ok "c_real returns data"
  else
    no "c_real run failed (see /tmp/bd.json)"
  fi
fi

# Secret hygiene: `brightdata add mcp --project` writes the literal token into
# .claude/settings.json, which is committed. Catch it before it reaches a commit.
leak=0
for f in "$R/.claude/settings.json" "$R/.mcp.json"; do
  [[ -f "$f" ]] || continue
  grep -Eq '"(API_TOKEN|api_key)"[[:space:]]*:[[:space:]]*"[^$][^"]{16,}"' "$f" && leak=1
done
[[ $leak -eq 0 ]] && ok "no API key in committed config" || no "API key leaked into committed config (.claude/settings.json or .mcp.json)"

echo "== signoz — all three signals =="
(cd "$R/otel-smoke" && node run.js >/dev/null 2>&1) && ok "otel smoke run (traces+metrics)" || no "otel smoke failed"
# Logs check must work in BOTH modes. The old version grepped stdout for "traceId",
# which only the Console exporter prints -- so it passed only while SigNoz was
# UNconfigured and failed the moment you wired it up. Assert arrival instead.
MARKER="verify-logs-$$-$(date +%s)"
LOGOUT=$(cd "$R/otel-smoke" && MARKER="$MARKER" node -e "
const {log}=require('./tracing.js'); const {trace}=require('@opentelemetry/api');
trace.getTracer('verify').startActiveSpan('preflight.logs',s=>{
  console.error('TRACEID='+s.spanContext().traceId);
  log('info', process.env.MARKER, {check:1}); s.end();
});
setTimeout(()=>process.exit(0),2500);
" 2>&1)
TID=$(printf '%s' "$LOGOUT" | sed -n 's/.*TRACEID=\([0-9a-f]*\).*/\1/p' | head -1)

if [[ -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q clickhouse; then
  # Self-hosted: strongest check -- confirm the record actually landed, correlated.
  CH=$(docker ps --format '{{.Names}}' | grep clickhouse | head -1)
  sleep 3
  got=$(docker exec "$CH" clickhouse-client -q \
    "SELECT trace_id FROM signoz_logs.distributed_logs_v2 WHERE body='$MARKER' LIMIT 1" 2>/dev/null | tr -d '[:space:]')
  if [[ -n "$got" && "$got" == "$TID" ]]; then
    ok "logs land in SigNoz, trace-correlated"
  elif [[ -n "$got" ]]; then
    no "log landed but trace_id mismatch (got '$got', span '$TID')"
  else
    no "log record never reached SigNoz (marker $MARKER)"
  fi
elif [[ -n "${SIGNOZ_INGESTION_KEY:-}" ]]; then
  # Cloud: cannot query the backend from here; assert the exporter raised no error.
  printf '%s' "$LOGOUT" | grep -qiE 'error|econnrefused|failed' \
    && no "logs exporter errored (see above)" || ok "logs exported to SigNoz cloud (no export errors)"
else
  # Console mode: nothing configured -- the record should print with a traceId.
  printf '%s' "$LOGOUT" | grep -q traceId \
    && ok "logs signal emits, trace-correlated (console mode)" || no "logs signal broken"
fi

echo; echo "$pass passed, $fail failed, $warn warned"
[[ $fail -eq 0 ]]
