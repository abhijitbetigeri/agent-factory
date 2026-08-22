# The Factory — design

> The app is the test run. The factory is the submission.

## The core idea: the three sponsors form one closed loop

Most teams will bolt three sponsor logos onto one app. The differentiator is wiring them
into a single control loop where each one does a job the other two can't:

```
            ┌──────────────────────────────────────────────┐
            │                                              │
            │   SigNoz  ── detects ──▶  Port  ── decides ──┼──▶ Bright Data
            │   (signal)                (governance)       │      (repairs)
            │      ▲                                       │           │
            │      └───────────── emits ────────────────────┘◀──────────┘
            │                                              
            └──────────────────────────────────────────────┘
```

- **SigNoz detects.** A verification span records `scraper.field_null_rate`. When it
  crosses threshold, a SigNoz alert fires a webhook. This is not "we also added logging" —
  observability is the *sensor* the factory acts on.
- **Port decides.** The webhook lands on a Port automation. Port holds the run context,
  evaluates a scorecard, and opens a **human approval gate** if the blast radius warrants it.
- **Bright Data repairs.** Port's approved action shells out to `brightdata scraper heal`,
  which proposes a fix behind its *own* approval gate, then `scraper approve` commits it.
- Loop closes: re-run, re-verify, new spans land in SigNoz, scorecard goes green.

Judges asked for exactly this: *"How observability feeds back into the factory: alerts,
retries, or human escalation."* Almost nobody will actually build the feedback edge.

## The pipeline

```
brief ──▶ plan ──▶ build ──▶ verify ──▶ approve ──▶ release ──▶ audit
  │        │         │          │           │           │         │
  └────────┴─────────┴──────────┴───────────┴───────────┴─────────┘
                    every stage = one OTel span in one trace
                    every stage = one Port entity + status transition
```

| Stage | What runs | Human in the loop? | Evidence produced |
|---|---|---|---|
| **brief** | Operator submits a product brief / change request via Port self-service action | submit | `Brief` entity |
| **plan** | Planner agent reads Context Lake (existing entities, constraints, past runs), emits a structured plan | **approval gate** | `Plan` entity w/ steps + risk |
| **build** | Coding agent (Claude Code) executes plan steps against the repo; Bright Data CLI (re)builds the data pipeline | no | commits, `BuildRun` entity |
| **verify** | Test suite + data contract check (schema + null-rate on scraped fields) + smoke request | no | `Verification` entity, scorecard |
| **approve** | Scorecard gates release; failing scorecard escalates to human | **approval gate** | approval record |
| **release** | Deploy; tag release entity | no | `Release` entity |
| **audit** | Trace + entity graph = full provenance of who/what changed | — | queryable in Port + SigNoz |

## Port data model (blueprints)

```
Brief ──▶ Plan ──▶ BuildRun ──▶ Verification ──▶ Release
                      │
                      ├──▶ AgentInvocation  (which agent, which model, tokens, duration)
                      └──▶ DataSource       (Bright Data collector_id, schema, health)
                                 │
                                 └──▶ HealEvent (trigger, diff, approver, outcome)
```

Relations matter more than the blueprints themselves — the graph is what makes "what
happened and why" answerable in one query. Every entity carries `trace_id` so a Port
entity links straight to its SigNoz trace.

## Scorecards (governance)

`production-readiness` on `Release`:
- Bronze: tests pass, build span has no ERROR status
- Silver: + data contract holds (null-rate < 5% on required fields), traces present for all stages
- Gold: + approval recorded by a human, no unresolved HealEvent

## Failure handling — must be demoable

Rehearse these three, they're the judging criteria in disguise:

1. **Scraper breaks** (site HTML changes) → null-rate metric spikes → SigNoz alert →
   Port automation → approval → `brightdata scraper heal` → `scraper approve` → re-run green.
2. **Build fails verification** → retry with failure context appended to the plan →
   second attempt succeeds → both attempts visible as sibling spans.
3. **Changing requirement mid-run** → submit a second brief that supersedes the first →
   show the factory re-planning rather than restarting, with the old plan retained for audit.

## The "run it again" test

Judges explicitly test whether it produces *one carefully rehearsed result*. Before the
demo, run the whole loop end-to-end from a **cold, different brief** you have not tried.
If it only works on the rehearsed brief, it's a prompt, not a factory.

## Anti-patterns called out in the brief

- ❌ A single giant prompt
- ❌ Fixed CI pipeline with an LLM bolted on
- ❌ A hardcoded HTML parser
- ❌ `console.log` as observability
