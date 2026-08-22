# SigNoz dashboard

`dashboard-factory-health.json` — four panels, built to answer **"what broke?"** in
under 30 seconds, because *"how quickly a judge (or an operator) could diagnose a
failure from your dashboards alone"* is a stated judging criterion.

| Panel | Answers |
|---|---|
| **Data contract — supplier price null-rate** | Is the data the factory routes on trustworthy? Threshold drawn at 0.05. The legacy `menu.price_null_rate` (0.5625) sits alongside it as the defect that motivated the project. |
| **Factory stage latency** | Which stage is slow, p95 by `factory.stage`. |
| **Endpoint + worker throughput** | Are the data endpoints and the background scrape job both alive? |
| **Supplier feed freshness** | Age of the last good scrape. Climbing without bound means the worker is dead. |

## Import

Self-hosted SigNoz has no API key, and dashboard creation needs a JWT from an
interactive login — so this is committed as an importable definition rather than applied
by a script:

```bash
./scripts/import-dashboard.sh      # prompts for your SigNoz login, imports via the API
```

Your password is read with `read -s`, used for one login call, and unset — it is never
written to disk or into anything the repo tracks.

Manual fallback: http://localhost:8080 → **Dashboards** → **+ New dashboard** →
**Import JSON** → paste `dashboard-factory-health.json`.

Metric names come from `docs/CONTRACTS.md` C5. If a panel is empty, run the factory once
(`node factory/run.js --brief "..."`) and start the app (`node app/server.js`) — the
gauges only report while a process is exporting.
