# Agentic Software Factory — project rules

## What this project is
An **Agentic Software Factory**: an executable, repeatable, observable system that takes a
product brief or change request and drives it through
`brief → plan → build → verify → approve → release → audit`.
The app it produces is the test run. **The factory is the deliverable.**

Design doc: `docs/factory-design.md`. Setup runbook: `PREP.md`.
**Starting a fresh session? Read `SESSION.md` first** — decisions already made, what is
verified, what is blocked.

## Non-negotiables (these are the judging criteria)
- No single-giant-prompt shortcuts, and no fixed CI pipeline with an LLM bolted on.
- Every stage must emit an OTel span and a Port entity. If it isn't traced, it didn't happen.
- Human approval gates are features, not friction. Keep `plan` and `release` gated.
- The factory must survive being run again on a brief nobody rehearsed.
- Failures, retries, and heal events are **first-class signals**, never buried log lines.

---

## Bright Data Scraper Studio — scraper settings

> Pinned here so the coding agent reuses them automatically instead of re-deriving
> commands. Version-controlled on purpose: this file *is* the scraper config.

```
BRIGHTDATA_CLI="npx --yes --package @brightdata/cli brightdata"
# Use case: Incident-to-Fix Factory (docs/incident-to-fix.md). Two collectors.
# c_real — live upstream status page, scraped during triage for "did a dependency
#          change under us?". Also the open-web credibility artifact.
SCRAPER_REAL_COLLECTOR_ID=c_mt4sihtk1e4weky7id
SCRAPER_REAL_TARGET_URL=https://www.githubstatus.com/

# c_mirror — the app's data source, and the deterministic break harness. Breaking it
#            is a commit to mirror/index.html that alters the price markup.
SCRAPER_MIRROR_COLLECTOR_ID=<c_xxxxxxxxxxxx>     # TODO: create still running
SCRAPER_MIRROR_TARGET_URL=https://abhijitbetigeri.github.io/agent-factory/mirror/

SCRAPER_REQUIRED_FIELDS=name,price               # `price` is the field that breaks
SCRAPER_NULL_RATE_THRESHOLD=0.05
```

**Run the pipeline:**
```bash
brightdata scraper run $SCRAPER_REAL_COLLECTOR_ID $SCRAPER_REAL_TARGET_URL --pretty
# batch:  --urls a,b,c   |   --input-file urls.txt
# fast single-URL path:  --sync --sync-timeout 50
```

**Create a scraper** (⚠️ 5–25 min — never on the critical path of a demo):
```bash
brightdata scraper create <url> "<natural language description of fields>"
```

**Repair a scraper when the site's HTML changes:**
```bash
brightdata scraper heal $SCRAPER_REAL_COLLECTOR_ID "<what is broken>" --url $SCRAPER_REAL_TARGET_URL
brightdata scraper approve $SCRAPER_REAL_COLLECTOR_ID --url $SCRAPER_REAL_TARGET_URL
# unattended (factory-driven): append --auto-approve --auto-save to `heal`
```

**Detection is our job, not the CLI's.** Bright Data never decides a scraper is broken.
The `verify` stage computes null-rate over `SCRAPER_REQUIRED_FIELDS` and emits
`scraper.field_null_rate`; the SigNoz alert on that metric is what triggers `heal`.
Never call `heal` blind — always pass the concrete failing-field message from the check.

**Auth:** `brightdata login` (browser) or `export BRIGHTDATA_API_KEY=...` in headless/CI.
Never inline a key into a command that gets committed.

### Setup state — DONE 2026-08-22
- Logged in; key synced into `.env` as `BRIGHTDATA_API_KEY` (gitignored). Balance **$50**.
- Zones `cli_unlocker` + `cli_browser` auto-created by `login`. Live `scrape` verified.
- Skills installed project-scoped: `.claude/skills/{brightdata-cli,scraper-builder}`.
- MCP `bright-data` declared in `.mcp.json` (5 tools: `search_engine`, `scrape_as_markdown`,
  `search_engine_batch`, `scrape_batch`, `discover`). Handshake verified.

> ⚠️ **Never run `brightdata add mcp --project`.** It writes the literal API token into
> `.claude/settings.json`, which is **committed**. `.mcp.json` instead uses
> `${BRIGHTDATA_API_KEY}` expansion. `verify.sh` now fails if a literal key appears in
> either file.

> ⚠️ **Launch Claude Code with the env loaded**, or `${BRIGHTDATA_API_KEY}` resolves to
> empty and the MCP server starts unauthenticated:
> ```bash
> set -a && . ./.env && set +a && claude
> ```

Only `SCRAPER_REAL_COLLECTOR_ID` / `SCRAPER_REAL_TARGET_URL` remain — both gated on the
use-case choice in `docs/idea-options.md`.

---

## Port

- Region: **US** (decided 2026-08-22). Locks the MCP URL below and `ingest.us.signoz.cloud`.
- MCP: `claude mcp add --transport http port https://mcp.us.port.io/v1` (EU would be `mcp.port.io`).
- Query the Context Lake through MCP before proposing changes — do not invent entity
  shapes that already exist.
- Use **AI Builder Plan mode first**, capture the plan, then Build. Never Build unreviewed.
- Blueprints — **12 total**. Every entity carries `trace_id`.
  - *Pipeline:* `Brief`, `Plan`, `BuildRun`, `Verification`, `Release`, `AgentInvocation`,
    `DataSource`, `HealEvent`
  - *Workspace (these win the Port track — do not skip them):* `Goal`, `TechnicalDecision`,
    `Risk`, `Service`. The track criterion is literally "project goals, technical choices,
    risk factors, and cataloged services." An empty workspace loses this prize.

## SigNoz

- **Deployment: SELF-HOSTED via docker compose** (decided 2026-08-22). `.env` sets
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`; `SIGNOZ_INGESTION_KEY` stays EMPTY.
  UI at http://localhost:8080. Cloud would instead be `https://ingest.<region>.signoz.cloud:443`
  with the key set and the endpoint empty — **set exactly one**, never both.
  `tracing.js` auto-detects; getting it wrong fails silently to the console.
- Manual spans required for each factory stage: `stage.plan`, `stage.build`,
  `stage.verify`, `stage.approve`, `stage.release`, under a root `factory.run` span.
- Emit span **events** for `scraper.heal.requested|approved|failed`.
- Set span status to ERROR on failure so stage failures are filterable.
- **All three signals are required, not just traces.** The track criterion names traces,
  metrics, *and* logs. Ship the OTel **logs** pipeline with `trace_id` correlation so a
  log line jumps straight to its span.
- Instrument **data endpoints and background jobs** specifically: the tracker's
  `/api/prices` endpoint and the scheduled re-scrape worker. Stage spans alone do not
  satisfy this criterion.
- The dashboard must let an operator diagnose a failure **in under 30 seconds** — latency,
  throughput, errors, and `scraper.field_null_rate` with its threshold drawn on it.
- `console.log` is not observability. If you're tempted to add one, add a span event —
  or a real OTel log record, now that we have that pipeline.

### Setup state — DONE 2026-08-22
Stack healthy (ingester 4317/4318, ClickHouse, UI 8080). End-to-end verified in ClickHouse:
- **Traces** — all 6 spans (`factory.run` + 5 stages) with correct nesting and status.
- **Metrics** — `factory.run.duration.*` and `scraper.field_null_rate` (the load-bearing one).
- **Logs** — arrive carrying `trace_id`/`span_id`.

> ⚠️ `log()` only correlates when called **inside an active span**. Emitted outside one it
> still ships, but with empty `trace_id` — it will not link back to anything in the UI.

> Inspect directly when the UI is ambiguous:
> ```bash
> docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
>   "SELECT name,statusCodeString FROM signoz_traces.distributed_signoz_index_v3 WHERE traceID='<id>'"
> ```

## Secrets
All keys live in `.env` (gitignored). Never commit a key, never paste one into a command
in a doc or a commit message.
