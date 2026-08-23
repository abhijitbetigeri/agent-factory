# Submission form answers

Copy-paste ready. Every claim here is backed by something in the repo.

---

## What does your project do?

**Mise OS is an operating system for physical work, and an agentic factory that builds
and repairs it.**

The OS takes a unit of physical work — a restock, an inter-branch transfer, a
procurement pickup — and routes it to whoever should execute it: an **AI agent**, a
**robot**, or a **human in the field**. It routes on live conditions: stock levels, par
levels, expiry windows, supplier prices. Anything above a risk threshold stops at a
human approval gate, because nobody should let an agent silently dispatch a robot to
move 10kg of near-expiry stock between sites.

**The problem it solves.** Restaurant supply chains make decisions from scraped web data
— menu prices, supplier availability. That data rots silently. A supplier site changes
its HTML, extraction starts returning nulls, nothing crashes, and the system keeps
making decisions on empty fields. Our own dataset proves it: **72 of 128 dish prices are
null — a 56.25% null rate** left behind by an earlier scraping pipeline. Routing had been
running on data that was 56% blind, and nothing was watching. No data contract, no
metric, no alert.

**Who it's for.** Restaurant operators and franchise procurement managers running
back-of-house inventory across branches — and, more broadly, anyone whose automated
decisions depend on scraped web data that can silently go stale.

**But the app is the test run; the factory is the deliverable.** The factory takes a
brief *or an incident* through `plan → build → verify → approve → release → audit`.
Every stage emits one OpenTelemetry span under a single `factory.run` trace and creates
one entity in Port carrying that trace id. It refuses to release when its data contract
fails — on a live run it prints `release SKIPPED (contract failed)` rather than
dispatching a robot on data it knows is blind.

Run it yourself with no accounts: `npm install && npm start`, then
`localhost:3000/console`.

---

## How did you use Bright Data in your project?

Bright Data has **two load-bearing roles**, and the whole self-repair loop is built on
the second one. Everything runs through the CLI from the terminal — no web dashboard.

**1. The supplier price feed the OS routes on.** Collector `c_mt4sjr912k58zc0ek7` scrapes
a supplier product listing and returns structured JSON — `product_name`, `sku_code`,
`price_usd {value, currency, symbol}`, `stock_status`. That feed is what the routing
arithmetic consumes, and it is refreshed by a background worker every two minutes.

**2. Upstream context during incident triage.** Collector `c_mt4sihtk1e4weky7id` scrapes
a live status page (githubstatus.com) to answer *"did a dependency change under us?"*
during triage. Notably, this collector initially extracted nothing but an empty array —
we repaired it with `brightdata scraper heal`, passing the concrete missing fields, and
it now returns `overall_status` plus a full per-component array. The repair mechanism was
proven on a real collector before we depended on it.

**The self-repair loop — the part we care about most.** Bright Data's docs are explicit
that **it never decides a scraper is broken. That detection is ours.** So we built it:
the `verify` stage computes a null-rate over the required fields, emits it as the metric
`supplier.price_null_rate`, and fails the data contract above 5%.

We then made that reproducible instead of hoping a real site would break on camera. A
script rewrites the source page's price markup — prices stop being text inside
`.price` and become an attribute on a renamed element — commits it, and GitHub Pages
republishes. The collector then fails loudly with
`parse_error: Parse error: value must be finite number`.

**And we never heal blind.** The repair prompt leads with the collector's own error
message, then states exactly what changed on the page and where the value now lives, and
which fields are unchanged. Measured result: **null-rate 100% → 0%, RECOVERED**, after
which `verify` passes and the release goes through. A `heal_event` entity lands in Port
with `outcome: resolved`, the failing fields, and the triggering metric value.

Scraper settings are version-controlled in `CLAUDE.md` so the coding agent reuses them
rather than re-deriving commands, and baseline JSON output is committed under `data/`.

---

## How did you use Port in your project?

Port is the factory floor — it holds the model, the graph, and the gates.

**13 blueprints, applied by an idempotent, dependency-ordered script**
(`scripts/apply-blueprints.sh`), so the workspace rebuilds from scratch in seconds:

- **Pipeline:** `brief`, `plan`, `build_run`, `verification`, `release`,
  `agent_invocation`, `data_source`, `heal_event`, `incident`
- **Workspace:** `goal`, `technical_decision`, `risk`, `factory_service`

That second group is deliberate. A catalog with no goals, no recorded technical choices
and no risks describes what ran but not *why* — so those blueprints hold the project's
goals, ADR-shaped decisions with alternatives and rationale, and risks scored by
likelihood × impact against the stage they threaten.

**Every factory run writes the graph.** `incident → brief → plan → build_run →
verification → release`, with `heal_event → data_source` hanging off it. Every entity
carries `trace_id`, so any node in Port jumps straight to its SigNoz trace. This is the
difference between a log of what happened and a queryable graph of what happened and why.

**Port owns the approval gates, not our code.** The `plan` entity sits at
`approval_status: pending` until a human moves it. We deliberately did not implement
approval as a boolean in the orchestrator — it belongs where the goals, risks and
decisions live. In our UI, a human approves by **watching a simulation of the dispatch**
— the robot's route, the near-expiry crate, the handoff — and that click writes
`approval_status: approved` and `approved_by: human (via simulation rehearsal)` back to
the Port entity. You approve a rehearsal of the physical action, not a JSON diff.

**Two entry points, one pipeline.** A human brief submitted through the console, or an
incident raised from a data-contract breach. `brief.origin` records which. The factory
therefore demonstrably *builds*, not just repairs.

The factory authenticates with Port machine credentials over REST so it runs unattended,
while the Port MCP server is connected for interactive querying of the catalog.

---

## How did you use SigNoz in your project?

**Observability is the sensor the factory acts on, not a report someone reads
afterwards.** SigNoz is self-hosted via Docker; all three signals are verified landing.

**Traces.** Every factory stage is a span under a single `factory.run` root:
`stage.brief`, `stage.incident`, `stage.plan`, `stage.build`, `stage.verify`,
`stage.approve`, `stage.release`, `stage.audit`. When the data contract breaches,
`stage.verify` is set to **ERROR** with the message `null-rate 0.5625 > 0.05`, so failed
stages are filterable rather than buried. Span events mark
`data_contract.breached`, `scraper.heal.requested` and `scraper.heal.approved` — failure
and self-repair are first-class signals.

*(We found and fixed a real bug here: the stage wrapper was setting span status OK
unconditionally after each stage body, silently overwriting the ERROR that `verify` sets.
Stage failures were invisible to filters until we caught it.)*

**Logs.** A full OTel logs pipeline, not `console.log`. Records are emitted inside the
active span, so they carry `trace_id` and `span_id` — a log line in SigNoz jumps straight
to the stage that produced it. Verified in ClickHouse.

**Metrics.** `supplier.price_null_rate` (the live data contract),
`menu.price_null_rate` (the 0.5625 legacy defect), `factory.stage.duration` (histogram,
tagged by stage), `http.server.requests`, `worker.scrape.duration`, and
`supplier.feed.age_seconds`.

**Data endpoints and background jobs are instrumented specifically**, since stage spans
alone don't cover them: the app's `/api/dispatch` and `/api/health` endpoints, and the
scheduled scrape worker, each emit their own spans and metrics.
*(Another real fix: the contract gauges were originally emitted only by the orchestrator,
so they went stale whenever nobody ran the factory. The worker now publishes them
continuously.)*

**How observability feeds back.** The null-rate metric crossing its threshold is what
opens an `Incident` in Port, blocks the release, and drives the Bright Data repair — then
the re-verification lands as new spans and the contract goes green. That closes the loop:
**SigNoz detects → Port decides, with a human → Bright Data repairs → SigNoz confirms.**

**One honest note:** the threshold evaluation currently lives in the factory's `verify`
stage rather than in a configured SigNoz alert rule, because SigNoz is self-hosted on
localhost and cannot webhook into a local factory without a tunnel. The metric, the red
span and the dashboard definition are all in place; the trigger is a poll rather than a
push.
