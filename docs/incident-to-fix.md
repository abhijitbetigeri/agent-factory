# The Incident-to-Fix Factory — chosen design

> **Decided 2026-08-22.** Idea #5, flipped flow. Supersedes the open question in
> `docs/idea-options.md`. Region US, budget under 12h, prize target = grand + all three tracks.

## The flip

Most factories start with a human brief. Ours starts with a **signal**. A SigNoz alert
is the entry point; the factory triages it, decides a fix path, and drives it to release
behind a human gate.

```
   SigNoz alert ──▶ Port automation ──▶ triage agent ──▶ fix path ──▶ human gate ──▶ release
   (the sensor)      (governance)       (reads traces)      │                          │
                                                            │                          ▼
                                          ┌─────────────────┴────────────┐        re-verify
                                          │                              │             │
                                   scraper_heal                     code_patch         │
                                (Bright Data repairs)              (agent opens PR)     │
                                          └──────────────┬───────────────┘             │
                                                         └───────────────────────────◀─┘
```

## Bright Data is NOT a garnish here — it has two load-bearing roles

This is idea #5's known weakness and the main thing to get right. Judges will notice a
"we also fetched a status page" bolt-on.

1. **BD is what breaks.** `c_mirror` scrapes the app's data source. When that page's HTML
   changes, null-rate on `price` spikes — **that is incident class #1**, and the fix path
   is `brightdata scraper heal`. Bright Data is both the failure and the repair.
2. **BD is how we triage.** `c_real` scrapes a live upstream status page
   (githubstatus.com) during triage to answer *"did a dependency change under us?"*
   That is the context-fetching role the brief describes.

So: SigNoz initiates, Port governs, Bright Data repairs **and** informs.

## The three incident classes

| Class | SigNoz alert | Fix path | Human gate |
|---|---|---|---|
| `data_source_broken` | `scraper.field_null_rate > 0.05` | `brightdata scraper heal` → `approve` → re-verify | **yes** — approve the patch |
| `endpoint_failing` | span status ERROR rate on `/api/*` | agent triages traces → patch → PR | **yes** — approve the PR |
| `performance_regression` | p95 latency over threshold | agent triages traces → patch → PR | **yes** |

Class #1 is the flagship and the one rehearsed for the video. Classes #2 and #3 share the
same triage→patch→PR machinery; #2 is the demoable one if time allows.

## The app under observation: PartsRadar

Deliberately thin. It exists to have incidents, not to be impressive.

- **Background job** — scheduled worker runs `brightdata scraper run $c_mirror`, writes JSON
- **Data endpoint** — `GET /api/parts` serves the scraped rows
- **Data endpoint** — `GET /api/health` returns freshness + last null-rate
- **Page** — table of parts, prices, and a visible "last scraped" timestamp

Those first two exist specifically to satisfy the SigNoz criterion *"metric tracking
across data endpoints and background jobs"* — stage spans alone do not cover it.

## Why the mirror exists

`c_mirror` targets `https://abhijitbetigeri.github.io/agent-factory/mirror/`, a fixture
page served from this repo. Breaking it is a commit that alters the price markup.

This is not a shortcut — it is the organizers' own prep instruction: *"Break something on
purpose: point at a page whose structure has changed and watch the auto-repair flow."*
A demo that waits for a real site to change is a demo that does not happen.

`c_real` targets a genuinely live page, so the "works on the open web" claim is real too.

## Port model

The 13 blueprints already applied. `incident` is the entry point for this use case:

```
incident ──▶ brief(origin=incident) ──▶ plan ──▶ build_run ──▶ verification ──▶ release
   │                                                                  │
   ├──▶ heal_event ──▶ data_source        (class #1, Bright Data path)
   └──▶ factory_service                    (what it affects)
```

`incident` carries `detected_by` (which alert fired), `signal` (the concrete number that
breached), `triage_summary`, `upstream_context` (BD-fetched), `fix_path`, and `trace_id`.

Every stage still emits an OTel span under one `factory.run` root, and every entity
carries `trace_id`, so any Port node jumps to its SigNoz trace.

## Demo video beats (3-5 min)

1. **Terminal** — break the mirror with a commit; the worker scrapes; nulls appear
2. **SigNoz** — `scraper.field_null_rate` crosses the threshold, alert fires, one trace
   shows the whole run with logs correlated
3. **Port** — an `Incident` entity appears, triaged, with upstream context attached,
   sitting at an approval gate
4. **Bright Data** — approve on camera → `scraper heal` → `scraper approve` → re-run
5. **Close** — scorecard goes green, loop diagram, "the factory is the deliverable"

## Cuts that stand

- ❌ class #3 (performance regression) as a live demo
- ❌ any PartsRadar feature beyond one table and one timestamp
- ❌ auth, multi-user, persistence beyond a JSON file
