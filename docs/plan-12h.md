# The 12-Hour Plan — Keychron Price Tracker Factory

> ⚠️ **The use case is NOT decided.** This plan was drafted against one candidate
> (a Keychron price tracker) to make the schedule concrete. The *timeline, prize
> mapping, cuts, and video beats are idea-agnostic and stand*; every app-specific
> detail is a placeholder. See `docs/idea-options.md` for the open decision.
>
> Fixed: region **US**, budget **under 12h**, target = grand prize + all three tracks.

## Prize criteria → build items

The grand prize is already what `docs/factory-design.md` describes. The three track
prizes name criteria our design did **not** cover. These are the gaps, and they are
cheap to close if we do it deliberately.

| Prize | Stated criterion | What we must build |
|---|---|---|
| **Grand** | all three in one complete pipeline | the closed loop: SigNoz detects → Port decides → Bright Data repairs → re-verify |
| **Port** | project goals | `Goal` blueprint, seeded with the 3 factory goals |
| | technical choices | `TechnicalDecision` blueprint (ADR-shaped: choice, alternatives, rationale) |
| | risk factors | `Risk` blueprint w/ likelihood × impact, linked to the stage it threatens |
| | cataloged services | `Service` blueprint — the tracker app, the orchestrator, the two collectors |
| **Bright Data** | pure terminal workflow | zero web UI in the video. Every BD action is a CLI call, on camera |
| | proper scraper rules config | scraper settings block in `CLAUDE.md` is version-controlled and is the config |
| | clean JSON output | `--pretty` output committed to `data/` as a reviewable artifact |
| | working auto-repair | the heal demo, below |
| **SigNoz** | active tracing | stage spans under one `factory.run` root — already proven in `otel-smoke/` |
| | **log collection** | **NEW: OTel logs signal, trace-correlated. We only had spans.** |
| | metric tracking on **data endpoints and background jobs** | **NEW: instrument the tracker's HTTP endpoints AND the scheduled re-scrape worker** |

The two bolded rows are real additions to scope. Everything else we already had.

## Port's five building blocks → what we ship

The brief names five building blocks. Judges will look for all five, so each one gets
exactly one visible artifact. Nothing more — we have 12 hours.

| Building block | Our artifact |
|---|---|
| Context Lake | the 12 blueprints + relations; `plan` stage **queries it via MCP before planning** |
| Workflow orchestration | the `factory.run` orchestrator, driven by a Port self-service action |
| AI agents | planner + coder, each logged as an `AgentInvocation` entity (model, tokens, duration) |
| Governance | `production-readiness` scorecard + the two approval gates |
| Interface layer | the operator dashboard — the run, its stages, its risks, its pending approval |

## The six factory judging criteria → where each is demonstrated

| Criterion | Where it shows |
|---|---|
| Faithfully understands brief + constraints | `plan` reads Context Lake constraints, not just the brief text |
| Coordinates agents, tools, human decisions | one trace showing planner → coder → BD CLI → approval gate |
| Tests and verifies what it produces | `verify` stage: tests + data contract + null-rate |
| **Handles failures, retries, changing requirements** | **scenario #2, restored — see below** |
| Operators can see what happened and why | SigNoz diagnosis dashboard + Port entity graph |
| **Can run again** | the cold-brief run at T+8:00. Non-negotiable. |

## The two-collector decision

Bright Data's `heal` repairs a scraper after a site's HTML changes. We cannot make
keychron.com change its HTML on demand, so a demo that waits for a real break is a
demo that doesn't happen. Two collectors, created **in parallel** at T+0:

- **`c_real`** → real Keychron listings. This is the credible artifact: real-world
  scrape, clean JSON, proves the pipeline works on the open web.
- **`c_mirror`** → a static mirror of that page we host on **GitHub Pages** from this
  repo. The "site change" is a commit that alters the price markup. Deterministic,
  reproducible, and genuinely a real HTML change that a real `heal` really repairs.

This is a demo harness, not a cheat — and it is **exactly what the organizers tell you
to do**. Their own prep advice: *"Break something on purpose: point at a page whose
structure has changed and watch the auto-repair flow."* Say so in the README and move on.

## Timeline

Hours are elapsed, not clock. Anything marked ⚠️ is on the critical path.

### T+0:00 → 0:30 — unblock everything, in parallel
Order matters: Bright Data **first**, because it gates the 5–25 min long pole.

1. ⚠️ `brightdata login` → immediately fire **both** `scraper create` calls, backgrounded
2. ⚠️ `gh repo create` + push — needed for GitHub Pages *and* for submission
3. Commit the mirror page to `/docs-site/`, enable Pages
4. SigNoz signup (US) → ingestion key → `.env`
5. Port signup (US) → `./scripts/setup-port-mcp.sh` → OAuth in `claude`
6. Me, while you're in browsers: draft all 12 blueprint JSON schemas offline

### T+0:30 → 2:30 — the spine
Promote `otel-smoke/` into a real `factory/` orchestrator. Stages
`brief→plan→build→verify→approve→release→audit`, each one span under `factory.run`.
Add the **OTel logs** pipeline (the SigNoz gap) with `trace_id` correlation.
Add a Port entity writer using machine creds — the API, not MCP, so it runs unattended.

### T+2:30 → 4:30 — Port workspace
All 12 blueprints. One self-service action (submit brief). Two approval gates
(`plan`, `release`). One automation (heal trigger from the SigNoz webhook).
One `production-readiness` scorecard. One dashboard that is the Port-track money shot.

### T+4:30 → 6:00 — the app (deliberately thin)
Keychron price tracker: one page, one table, one sparkline, reading scraped JSON.
An instrumented `/api/prices` endpoint and a scheduled re-scrape worker — those two
exist specifically to satisfy "data endpoints and background jobs."
The app must **genuinely consume fresh scraped data** — "whether the data feeding your
factory is fresh, structured, and actually used by your app" is a stated Bright Data
criterion. Read the real collector output, show a scrape timestamp on the page.

**Resist feature creep otherwise. The app is the test run, not the deliverable.**

### T+5:45 → 6:00 — the diagnosis dashboard
One SigNoz dashboard, built to answer *"what broke?"* in under 30 seconds, because
"how quickly a judge could diagnose a failure from your dashboards alone" is a stated
criterion. Four panels only: stage **latency** p50/p95, scrape **throughput** + freshness,
**error** rate by stage, and `scraper.field_null_rate` with the alert threshold drawn on it.
Heal events overlay as annotations — first-class signals, not buried log lines.

### T+6:00 → 8:00 — close the loop ⚠️ THE DIFFERENTIATOR
`verify` computes null-rate over `price` → emits `scraper.field_null_rate` →
SigNoz alert → webhook → Port automation → human approval gate →
`brightdata scraper heal --auto-approve --auto-save` → re-verify → scorecard green.

If time runs out anywhere else, it runs out here last. Almost nobody else will
build this edge, and it is the entire grand-prize argument.

### T+8:00 → 9:30 — cold-brief test + README
Run the factory on a brief nobody rehearsed. If it only works on the rehearsed one,
it's a prompt, not a factory. README breaks down what was built, honestly.

### T+9:30 → 11:00 — demo video (3–5 min)
### T+11:00 → 12:00 — buffer. Something will break.

## Explicit cuts (say these out loud so nobody re-adds them)

- ⚠️ **Scenario #2 (retry-with-context) is RESTORED as a live demo.** "How it handles
  failures, retries, and changing requirements" is a named judging criterion, and the
  retry is nearly free: when `verify` fails, append the failure context to the plan and
  re-run `build`. Both attempts appear as sibling spans. Budget: 30 min inside Phase 4.
- ❌ Scenario #3 (mid-run re-plan on a superseding brief) stays cut as a live demo.
  If the cold-brief run happens to produce one, screenshot it. Do not build for it.
- ~~❌ Port AI Builder~~ **REVERSED.** The brief explicitly points at AI Builder and at
  the Plan-vs-Build distinction. It is also simply *faster* than hand-authoring 12
  blueprint schemas. Use **Plan mode first**, capture the proposed plan as evidence,
  review it, then Build. The captured plan is itself a submission artifact.
- ❌ Any app feature beyond one table and one chart.
- ❌ Auth, multi-user, persistence beyond a JSON file.

## Demo video beats (the four things the brief asks to see)

1. **Terminal workflow** (0:00–1:00) — submit brief, watch stages stream, pure CLI
2. **Port dashboard** (1:00–2:00) — the entity graph, goals/risks/decisions, approval gate
3. **Live SigNoz** (2:00–3:00) — one trace, all stages, logs correlated, the metric
4. **Auto-fix in Bright Data** (3:00–4:30) — commit the markup break, alert fires,
   Port asks for approval, you click approve on camera, `heal` runs, scorecard goes green
5. **Close** (4:30–5:00) — the loop diagram, one sentence: the factory is the deliverable
