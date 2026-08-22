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

SigNoz **v0.138.0** self-hosted exposes no unauthenticated dashboard API, and the JWT
login route is not reachable — `POST /api/v1/login` is served by the static handler and
never reaches the server's route table. So import through the UI:

```bash
./scripts/import-dashboard.sh    # validates the JSON, checks SigNoz, prints the steps
```

then: http://localhost:8080/dashboard → **New dashboard** → **Import JSON** → paste
`dashboard-factory-health.json`.

## The `image` field is mandatory

The importer validates `image` **before** it looks at the schema, and rejects the whole
file with a generic *"Error loading JSON file"* if it is missing:

```js
let n = Ca(JSON.parse(i));
if (!xn(n.image)) { /* rejected */ }
```

It must be an `/assets/Icons/...` or `/assets/Logos/...` path, or a base64 image. This
file uses `/assets/Icons/eight-ball`. Two import attempts failed on this before the
frontend bundle was read — the error message names neither the field nor the reason.

## Metric queries are not expression queries

The traces/logs form — `aggregations: [{"expression": "avg(x)"}]` — is rejected for the
metrics signal:

```
unknown field "expression" in query spec for MetricAggregation
```

Metric aggregations take `metricName`, `temporality`, `timeAggregation`,
`spaceAggregation`, `reduceTo`. Temporality must match what is actually stored, or the
panel renders empty. Checked in ClickHouse rather than assumed:

| Metric | Type | Temporality |
|---|---|---|
| `supplier.price_null_rate`, `menu.price_null_rate`, `supplier.feed.age_seconds` | Gauge | Unspecified |
| `factory.stage.duration.max`, `worker.scrape.duration.max` | Gauge | Unspecified |
| `http.server.requests` | Sum | Cumulative |

## Schema

`schemaVersion: v6` — the format SigNoz v0.138 expects: `spec.panels` keyed by uuid,
with `spec.layouts[0].spec.items` referencing them by `$ref`. An earlier hand-built
version used the legacy top-level `widgets` array and SigNoz rejected it outright with
*"Error loading JSON file"*. The shape here is modelled on SigNoz's own published
dashboards (github.com/SigNoz/dashboards), not guessed.

Queries use metric-signal builder queries with expressions like
`avg(supplier.price_null_rate)` and `p95(factory.stage.duration)`.

## Metric names

Histograms are stored with `.bucket` / `.count` / `.sum` / `.max` / `.min` suffixes.
Referencing the bare name gives an **empty panel**, so this dashboard points at
`factory.stage.duration.bucket` and `worker.scrape.duration.max`, not the base names.
Verified present in ClickHouse before committing.

Metric names come from `docs/CONTRACTS.md` C5. If a panel is empty, run the factory once
(`node factory/run.js --brief "..."`) and start the app (`node app/server.js`) — the
gauges only report while a process is exporting.
