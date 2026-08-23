# 5-minute video script

Covers the required sections: **About the project · Tech stack and architecture · How
sponsor tools were used · Demo · Learning and growth.**

**Before you roll**
- Get the feed to the healthy side: panel 03 → either **redesign** button → wait ~90s →
  **Re-check the feed** → the pill must read **feed healthy**.
  (The collector adapts each time it is repaired, so neither markup is permanently
  "broken" — the pill is the truth.)
- Tabs open: `localhost:3000/console` · `app.us.port.io` · `localhost:8080/traces`
- App must be started with `.env` sourced, or it silently runs in demo mode and exports
  no telemetry: `set -a && . ./.env && set +a && npm start`

---

## 1 · About the project · 0:00–0:40

**Screen:** landing page hero → console panel 00 (the red bars)

> Mise OS is an operating system for physical work. It takes a unit of work — a restock,
> a transfer between restaurant branches — and routes it to whoever should execute it:
> an AI agent, a robot, or a human in the field.
>
> But the app isn't the point. The *factory that builds it* is. And it starts from a real
> defect: 72 of the 128 dish prices in this dataset are null. Routing has been running on
> data that's 56% blind, and nothing was watching — no data contract, no metric, no
> alert. That's the gap this fills.

---

## 2 · Tech stack and architecture · 0:40–1:30

**Screen:** the loop diagram → panel 01 mid-run

> Node orchestrator, OpenTelemetry throughout, no framework.
>
> The pipeline is `brief → plan → build → verify → approve → release → audit`. Two entry
> points into it: a human brief, or a signal. Every stage is one span under a single
> `factory.run` trace, and one entity in Port carrying that trace id. If it isn't traced,
> it didn't happen.
>
> The architecture is a **loop**, not a pipeline: observability detects, governance
> decides with a human in it, the data layer repairs itself, and then it re-verifies.

---

## 3 · Sponsor tools · 1:30–2:30

**Screen:** Port graph → SigNoz trace → panel 03

**Port**
> The factory produces a graph, not a log. Brief, plan, build, verification, release —
> all linked, so "what happened and why" is one query. And the approval gates are Port's,
> not a boolean in our code. They live where the goals, risks and technical decisions live.

**Bright Data**
> We didn't pick it because we needed to scrape. We picked it because scrapers fail
> *silently* — a site redesigns, extraction returns nulls, nothing crashes, and you keep
> deciding on empty data. Bright Data can repair its own extraction. But it never decides
> it's broken — that's ours. We compute the null-rate, name the failing fields, and hand
> it the collector's own error message.

**SigNoz**
> Observability as a sensor, not a report. The null-rate is a metric, the breach is a red
> span, and that's what the factory acts on.

---

## 4 · Demo · 2:30–4:40

| Time | Do | Say |
|---|---|---|
| 2:30 | Panel 01 → **Submit brief** | One brief. Routed across an agent, a robot and a human — surplus moves before anything is bought, nearest-expiry first. Then it stops. Release is gated. |
| 2:55 | Panel 02 → **Approve dispatch**, then 02b → **Load simulation** | You don't approve a JSON diff. This is generated from the dispatch that just ran. The human watches what the robot will do. |
| 3:20 | Port tab — entity graph, then goals/risks/decisions | Every stage an entity, every entity carrying the trace id. |
| 3:40 | SigNoz → traces → filter `factory-orchestrator` | One trace, every stage. `verify` is red — contract breached. |
| 3:55 | Panel 03 → **Supplier ships a redesign** · ⏸ **pause ~90s** · **Re-check the feed** | A real commit changes the page's markup. The collector falls over — `parse error: value must be finite number`. Nothing crashed. **We** caught that, not Bright Data. |
| 4:15 | Panel 01 → **Trigger incident** | Null-rate 100%. Failing fields named. Release **SKIPPED**. |
| 4:25 | **Repair the collector** · ⏸ **pause** · resume on `RECOVERED` → **Trigger incident** | Bright Data rewrites its extraction against the new structure — and we don't ask it to guess, we hand it the collector's own error. 100% to zero. Re-verify, release unblocks. |

**⏸ Pause recording for both waits** (Pages ~90s, heal 3–10 min). Filming dead air is the
fastest way to blow the 5-minute cap.

---

## 5 · Learning and growth · 4:40–5:00

> The hardest part wasn't wiring three APIs — it was that Bright Data deliberately never
> tells you a scraper is broken. Detection had to be ours. Building that check, and the
> metric it feeds, is what turned three integrations into one loop.
>
> Each of these does a job the other two can't. Most teams will integrate all three. The
> question is whether they *feed* each other.

---

## Lines worth not fumbling

- *"Bright Data never decides a scraper is broken — that's our job."*
- *"You don't approve a JSON diff — you watch what the robot will do."*
- *"If it isn't traced, it didn't happen."*
- *"Most teams will integrate all three. The question is whether they feed each other."*

## If something breaks mid-take

| Symptom | Fix |
|---|---|
| Console unresponsive | app died — `set -a && . ./.env && set +a && npm start` |
| Panels show dashes | app started without `.env` → demo mode |
| Feed pill says degraded when it should be healthy | click the *other* redesign button, wait ~90s, **Re-check the feed** |
| Heal returns 409 | a refactor job is still running server-side — wait, don't retry |
