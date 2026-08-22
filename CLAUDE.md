# Agentic Software Factory — project rules

## What this project is
An **Agentic Software Factory**: an executable, repeatable, observable system that takes a
product brief or change request and drives it through
`brief → plan → build → verify → approve → release → audit`.
The app it produces is the test run. **The factory is the deliverable.**

Design doc: `docs/factory-design.md`. Setup runbook: `PREP.md`.

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
SCRAPER_STUDIO_COLLECTOR_ID=<c_xxxxxxxxxxxx>     # TODO: fill after `scraper create`
SCRAPER_TARGET_URL=<https://...>                 # TODO
SCRAPER_REQUIRED_FIELDS=<field_a,field_b>        # drives the null-rate health check
SCRAPER_NULL_RATE_THRESHOLD=0.05
```

**Run the pipeline:**
```bash
brightdata scraper run $SCRAPER_STUDIO_COLLECTOR_ID $SCRAPER_TARGET_URL --pretty
# batch:  --urls a,b,c   |   --input-file urls.txt
# fast single-URL path:  --sync --sync-timeout 50
```

**Create a scraper** (⚠️ 5–25 min — never on the critical path of a demo):
```bash
brightdata scraper create <url> "<natural language description of fields>"
```

**Repair a scraper when the site's HTML changes:**
```bash
brightdata scraper heal $SCRAPER_STUDIO_COLLECTOR_ID "<what is broken>" --url $SCRAPER_TARGET_URL
brightdata scraper approve $SCRAPER_STUDIO_COLLECTOR_ID --url $SCRAPER_TARGET_URL
# unattended (factory-driven): append --auto-approve --auto-save to `heal`
```

**Detection is our job, not the CLI's.** Bright Data never decides a scraper is broken.
The `verify` stage computes null-rate over `SCRAPER_REQUIRED_FIELDS` and emits
`scraper.field_null_rate`; the SigNoz alert on that metric is what triggers `heal`.
Never call `heal` blind — always pass the concrete failing-field message from the check.

**Auth:** `brightdata login` (browser) or `export BRIGHTDATA_API_KEY=...` in headless/CI.
Never inline a key into a command that gets committed.

---

## Port

- Region: `<EU|US>` — TODO, locks the MCP URL below.
- MCP: `claude mcp add --transport http port https://mcp.port.io/v1` (US: `mcp.us.port.io`).
- Query the Context Lake through MCP before proposing changes — do not invent entity
  shapes that already exist.
- Use **AI Builder Plan mode first**, capture the plan, then Build. Never Build unreviewed.
- Blueprints: `Brief`, `Plan`, `BuildRun`, `Verification`, `Release`, `AgentInvocation`,
  `DataSource`, `HealEvent`. Every entity carries `trace_id`.

## SigNoz

- Endpoint `https://ingest.<region>.signoz.cloud:443`, key from env
  (`SIGNOZ_INGESTION_KEY`) — never hardcoded.
- Manual spans required for each factory stage: `stage.plan`, `stage.build`,
  `stage.verify`, `stage.approve`, `stage.release`, under a root `factory.run` span.
- Emit span **events** for `scraper.heal.requested|approved|failed`.
- Set span status to ERROR on failure so stage failures are filterable.
- `console.log` is not observability. If you're tempted to add one, add a span event.

## Secrets
All keys live in `.env` (gitignored). Never commit a key, never paste one into a command
in a doc or a commit message.
