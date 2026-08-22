# Agentic Software Factory

An executable, repeatable, observable system that takes a product brief or change request
and drives it to shipped software — coordinating agents, tools and human decisions along
the way.

**The app it produces is the test run. The factory is the submission.**

Built across three layers:

| Layer | Tool | Role |
|---|---|---|
| Factory / control plane | **Port** | context lake, workflow orchestration, governance, approval gates, operator view |
| Raw material | **Bright Data Scraper Studio** | live web data pipeline, self-healing when sites change |
| Nervous system | **SigNoz** | traces, metrics, logs — and the *sensor* that triggers repair |

## The thesis in one diagram

```
SigNoz detects  ──▶  Port decides  ──▶  Bright Data repairs  ──┐
     ▲                (+ human approval gate)                  │
     └──────────────────── re-verify ────────────────────────────┘
```

Three sponsors, one closed loop — not three integrations sitting next to each other.
Full reasoning in [docs/factory-design.md](docs/factory-design.md).

## Layout

```
PREP.md                  setup runbook — accounts, exact commands, day-of plan
CLAUDE.md                project rules; pins Bright Data scraper config (version-controlled)
docs/factory-design.md   the design + demo script
otel-smoke/              runnable OTel trace/metric contract, works with no account
scripts/setup-*.sh       one-shot setup for Bright Data and Port MCP
scripts/verify.sh        preflight — run before building and before demoing
.env.example             copy to .env
```

## Quick start

```bash
cp .env.example .env         # then fill in keys
./scripts/setup-brightdata.sh
./scripts/setup-port-mcp.sh
cd otel-smoke && npm install && npm run smoke && npm run smoke:fail
./scripts/verify.sh
```
