# Pre-hackathon prep — Agentic Software Factory (Port × Bright Data × SigNoz)

Everything below was verified against live docs/CLIs on 2026-08-22 unless marked
**[needs you]** (account signup / OAuth — cannot be done from a non-interactive session).

Read [docs/factory-design.md](docs/factory-design.md) first — it's the actual thesis.
This file is the setup runbook.

---

## 0. Environment — already verified on this machine ✅

| Tool | Version | Status |
|---|---|---|
| Node | v20.20.2 | ✅ (Bright Data CLI needs ≥20) |
| npm | 10.8.2 | ✅ |
| Docker | 29.4.0 | ✅ (needed only for self-hosted SigNoz) |
| gh | 2.95.0 | ✅ |
| Bright Data CLI | 0.3.5 via npx | ✅ runs, all subcommands confirmed |
| Port MCP | — | ⬜ not yet added |
| SigNoz | — | ⬜ no account/key yet |

---

## 1. Accounts to create **[needs you]** — do this first, ~20 min

| Service | URL | What you need out of it |
|---|---|---|
| Port | app.port.io (or app.us.port.io) | org + login; note **region (EU vs US)** — it changes every URL below |
| Bright Data | brightdata.com → Scraper Studio | API key + some credit balance |
| SigNoz | ~~cloud trial~~ → **self-hosted, no account needed** | nothing — `foundryctl cast -f casting.yaml` runs it locally on :8080 |

Also worth doing: play with **demo.port.io** (no signup) to see a populated catalog before
you model your own.

---

## 2. Port setup — ~40 min

### 2a. Connect Claude Code to Port over MCP **[needs you: OAuth]**

Pick your region. Simple form:

```bash
# EU
claude mcp add --transport http port https://mcp.port.io/v1
# US
claude mcp add --transport http port https://mcp.us.port.io/v1
```

Explicit form with the read-only header (`0` = full access per your RBAC, `1` = read-only):

```bash
claude mcp add-json port '{"type":"stdio","command":"npx","args":["-y","mcp-remote","https://mcp.port.io/v1","--header","x-read-only-mode: 0"]}'
```

Then run `claude` and complete the browser OAuth. Session persists ~30 days.
Verify with: *"list all blueprints in my Port org"*.

For CI / unattended runs you want **machine credentials** (client-credentials flow) rather
than OAuth — set that up before demo day, not during it.

### 2b. Learn AI Builder: Plan mode vs Build mode

- **Plan mode** — describe intent, it proposes the data model / workflow / dashboard changes. Review, don't apply.
- **Build mode** — applies them to your org.

Rule for the hackathon: **always Plan first, screenshot the plan, then Build.** That
screenshot is your "human stays in control" evidence for judges.

### 2c. Prototype the small loop (do this BEFORE the event)

Model the minimum viable factory, per [docs/factory-design.md](docs/factory-design.md):
blueprints `Brief → Plan → BuildRun → Verification → Release`, one self-service action to
submit a brief, one automation chaining the stages, one approval gate, one scorecard, one
dashboard. Use AI Builder to generate it, then hand-fix.

**Success criterion:** submit a toy brief in the Port UI and watch it move through all
seven stages with one human approval. Don't touch a real app until this works.

---

## 3. Bright Data setup — ~40 min

### 3a. Install + auth **[needs you: browser login]**

```bash
curl -fsSL https://cli.brightdata.com/install.sh | sh    # or: npm i -g @brightdata/cli
brightdata login                                          # opens browser, stores API key
brightdata budget                                         # confirm balance
```

Headless/CI: `export BRIGHTDATA_API_KEY=...`

### 3b. Install the agent skills (this is the "lives inside the workflow" point)

```bash
brightdata skill list
brightdata skill add brightdata-cli
brightdata skill add scraper-builder
brightdata add mcp --agent claude-code --project    # writes .mcp.json entry
```

Confirmed available skills: `search`, `scrape`, `data-feeds`, `bright-data-mcp`,
`bright-data-best-practices`, `brightdata-cli`, `design-mirror`,
`python-sdk-best-practices`, `scraper-builder`.

### 3c. Build one scraper end to end

```bash
brightdata scraper create https://news.ycombinator.com \
  "Extract top stories: title, url, points, author, comment_count"
# → takes 5-25 min, returns a Collector ID: c_*
brightdata scraper run c_xxxxxxxx https://news.ycombinator.com --pretty
```

⚠️ **`scraper create` takes 5–25 minutes.** Do not discover this at 11am on demo day.
Create your real collector *the night before* and commit the ID.

### 3d. Pin settings in the rules file (explicit judging criterion)

Already scaffolded in [CLAUDE.md](CLAUDE.md) — fill in the collector ID after 3c.

### 3e. Rehearse auto-repair (explicit judging criterion)

```bash
brightdata scraper heal c_xxxxxxxx \
  "points and comment_count return null since the site redesign" \
  --url https://news.ycombinator.com
brightdata scraper approve c_xxxxxxxx --url https://news.ycombinator.com
# unattended: brightdata scraper heal ... --auto-approve --auto-save
```

**Critical detail from the docs:** *"You are the detector. The CLI never decides on its own
that a scraper is broken."* Bright Data will not tell you it's broken — **you** must supply
the detection. That's precisely why SigNoz is the sensor in this design. Build the
null-rate check as a first-class verification step; it's the seam that makes the loop work.

To rehearse: point the collector at a page whose structure genuinely differs (an archived
vs. current layout), let the null-rate check fail, and drive the heal from the alert.

---

## 4. SigNoz setup — ~30 min

### 4a. Exporter config

> **DECIDED 2026-08-22: we self-host.** The stack is already running — see the SigNoz
> section of `CLAUDE.md`. Use `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` and no
> ingestion key. The cloud recipe below is kept only as the fallback path.

Node instrumentation — zero-code path:

```bash
npm install --save @opentelemetry/api @opentelemetry/auto-instrumentations-node
```

```bash
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT="https://ingest.<region>.signoz.cloud:443"
export OTEL_EXPORTER_OTLP_HEADERS="signoz-ingestion-key=<your-key>"
export OTEL_SERVICE_NAME="factory-orchestrator"
export OTEL_NODE_RESOURCE_DETECTORS="env,host,os"
export NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register"
node app.js
```

A ready-to-run smoke test lives in [otel-smoke/](otel-smoke/) — see its README.

### 4b. Instrument the *factory*, not just the app

Auto-instrumentation gives you HTTP spans for free. That is table stakes and won't score.
Add **manual spans for factory stages** — that's what makes a judge able to read a run:

- root span `factory.run` with attributes `brief.id`, `run.id`, `agent.model`
- child spans: `stage.plan`, `stage.build`, `stage.verify`, `stage.approve`, `stage.release`
- `stage.approve` should carry `approval.human=true|false` and `approval.actor`
- span events (not log lines) for `scraper.heal.requested` / `.approved` / `.failed`
- set span status ERROR on failure so it's filterable

### 4c. Metrics + alert (this is the feedback edge)

- `scraper.field_null_rate` (gauge, per field) ← the trigger
- `factory.run.duration` (histogram), `factory.stage.failure` (counter)
- One SigNoz **alert** on null-rate → webhook → Port automation. Build this edge early;
  it's the piece that turns three integrations into one system.

### 4d. Dashboard

One dashboard a judge can read cold: run throughput, p95 stage latency, failure count by
stage, heal events over time. Rehearse the sentence: *"this run went red here, and here's why."*

---

## 5. Day-of running order

| Time | Do |
|---|---|
| T-1 night | `scraper create` (slow!), Port blueprints + workflow prototyped, SigNoz key in `.env` |
| First hour | Wire the loop skeleton end-to-end with a **stub** app. Prove brief→release works empty. |
| Then | Drop the real app in as a stage. Real data from the collector. |
| Then | Build the SigNoz alert → Port automation → heal edge. |
| Last 90 min | **Freeze features.** Rehearse the 3 failure demos + one cold, unrehearsed brief. |

## 6. Demo script (3 stages, ~3 min)

1. **Submit a brief** live, in the UI. Show the plan appear, approve it, watch it build and release.
2. **Break the web.** Point at the changed page. Null-rate spikes → SigNoz alert → Port
   escalation → approve heal → green. Narrate from the dashboard, not from your memory.
3. **Run it again** with a brief the judges pick, or one you've never run. This is the
   whole submission in 40 seconds.

## 7. Open decisions

- **Region: EU or US?** Locks Port MCP URL and SigNoz endpoint. Pick once, put in `.env`.
- **What app does the factory build?** Keep it small and data-fed. Candidates:
  a competitive price/availability tracker, a job-market radar, an event/CFP aggregator.
  Recommendation: something with an obvious *required field* whose disappearance is
  visually obvious when the scraper breaks (a price, a score, a count).
- **Team + repo access.** This repo is local-only so far — push it and add teammates
  before the event so nobody is doing git plumbing on the clock.
