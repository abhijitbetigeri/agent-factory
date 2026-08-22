# OTel smoke test

Proves the trace/metric shape the factory must emit, before the factory exists.
Verified working on Node v20.20.2 (2026-08-22).

## Run with no account (console exporter)
```bash
npm install
npm run smoke        # happy path  → factory.run OK, released
npm run smoke:fail   # broken path → verify fails, escalates
```

## Run against self-hosted SigNoz — THIS IS WHAT WE USE
Stack is cast by `foundryctl cast -f casting.yaml` from the repo root. No key: a
self-hosted ingester accepts unauthenticated OTLP.
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
npm run smoke
```
Verified end-to-end 2026-08-22 against SigNoz v0.138.0 — traces, metrics and logs all
land. Look for service `factory-orchestrator` in SigNoz → Services (UI on :8080).

## Run against SigNoz Cloud (fallback path)
```bash
export SIGNOZ_INGESTION_KEY=...      # from SigNoz Cloud settings
export SIGNOZ_REGION=us              # or eu / in
npm run smoke
```

> ⚠️ Set **exactly one** of `OTEL_EXPORTER_OTLP_ENDPOINT` / `SIGNOZ_INGESTION_KEY`.
> With neither, `tracing.js` falls back to the console exporter — the run looks green
> and every span is discarded. The banner it prints on startup names the active mode.

## What it emits — this is the contract
```
factory.run                     (run.id, brief.id, agent.model)
├── stage.plan                  (plan.steps, approval.required)
├── stage.approve               (approval.human, approval.actor, approval.gate)
├── stage.build                 (build.agent, build.files_changed)
├── stage.verify                (verify.required_fields, scraper.field_null_rate)
│     └── event: scraper.heal.requested   ← fires only on the broken path
└── stage.release               (release.version, release.strategy)
      event on root: factory.escalated    ← fires only on the broken path
```

Metrics: `factory.run.duration` (histogram, tagged `outcome`),
`factory.stage.failure` (counter, tagged `stage`),
`scraper.field_null_rate` (gauge, tagged `field` + `collector`).

`scraper.field_null_rate` is the metric the SigNoz alert watches. That alert is the
trigger for the whole self-repair loop — see `../docs/factory-design.md`.
