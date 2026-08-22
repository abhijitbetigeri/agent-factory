# Mise OS — an operating system for physical work, and the factory that builds it

**Agentic Software Factory hackathon · Port × Bright Data × SigNoz**

> The app is the test run. The factory is the deliverable.

Mise OS routes a unit of physical work — a restock, an inter-branch transfer, a
procurement pickup — to whoever should execute it: **an AI agent**, **a robot**, or **a
human in the field**. The factory is what builds and repairs Mise OS, and it is started
by a *signal* rather than by a person.

---

## The premise: a real defect, not a synthetic one

Mise OS routes food between restaurant branches, and every routing decision is
arithmetic over scraped menu and supplier data. The dataset it inherited was assembled
by an earlier scraping pipeline — search, then a generic page scrape, then LLM
extraction — which failed silently on prices. There is a measurable hole to prove it:

```
menu.price_null_rate = 0.5625      # 72 of 128 dish prices are null
```

Routing was running on data that is 56% blind, and nothing was watching — no data
contract, no metric, no alert. That is the gap this fills.

---

## The loop

```
   SigNoz alert ──▶ Port automation ──▶ triage ──▶ fix path ──▶ human gate ──▶ release
   (the sensor)      (governance)                     │                          │
                                                      ▼                          ▼
                                       brightdata scraper heal              re-verify
                                       (Bright Data repairs)                     │
                                                      └──────────────────────────┘
```

Each tool does a job the other two cannot:

| Tool | Role |
|---|---|
| **SigNoz** | The nerves. Traces every stage, endpoint and background job. Its alerts *start* the factory. |
| **Port** | The factory floor. Builds Mise OS, holds goals/decisions/risks/services, gates plan and release. |
| **Bright Data** | The senses — **and** the repair. The supplier feed is what breaks, and `scraper heal` is what fixes it. |

Bright Data is deliberately not a garnish: the feed it scrapes is the thing that fails,
so it is both the failure mode and the remedy.

---

## What the factory does

`brief | incident → plan → build → verify → approve → release → audit`

Two entry points, one pipeline — so the factory demonstrably **builds**, not just repairs:

```bash
node factory/run.js --brief "Route the Downtown tomato shortage"   # a human asks
node factory/run.js --incident data_source_broken                  # a signal asks
```

Every stage is one OTel span under a single `factory.run` root. Every stage is one Port
entity carrying that run's `trace_id`, so any node in the Port graph jumps straight to
its SigNoz trace. **If it is not traced, it did not happen.**

A run produces a real routing decision from the vendored Mise data:

```
Transfer 10kg, buy net 26kg @ $2.05 = $53.3
  [robot] transfer: 10kg from Marina (expires in 2d, use first)
  [human] handoff: Crate handed to the cook at the service pass
  [agent] procure: Only the NET shortage is bought: 26kg @ $2.05/kg
```

Surplus moves before anything is bought; a branch below its own par cannot donate;
nearest-expiry stock goes first. Only the *net* shortage reaches procurement.

---

## You approve the rehearsal, not the diff

`app/` generates a simulation **from the dispatch the factory just produced** — this
donor branch, this crate, this expiry window, this path, this handoff. A different
shortage draws a different simulation. The human watches what the robot will do and
approves *that*; the click writes `approval_status` back to Port.

```bash
node app/server.js        # http://localhost:3000
```

**Falsifiable:** change the branch numbers in `factory/mise.js`, re-run the factory,
reload. The simulation must show a different donor and quantity. If it does not, it is
a hardcoded demo.

The rehearsal is what the human approves against, and the approved plan is what would
deploy to a physical robot. The simulation is the gate, not a decoration.

---

## The self-healing edge

```bash
./scripts/break-mirror.sh        # a real commit that restructures the price markup
node factory/run.js --incident data_source_broken
node factory/heal.js             # detect → human gate → repair → re-verify
```

The supplier page's prices stop being text inside `.price` and become an attribute on a
renamed element — the kind of change a site redesign makes. GitHub Pages republishes,
and the contract catches it:

```
supplier null-rate 100.0%  (threshold 5%) -> FAIL
failing fields: name, price
release SKIPPED (contract failed)
```

**Detection is ours, not the CLI's.** Bright Data never decides a scraper is broken.
`verify` computes the null-rate, and `heal.js` passes the *concrete failing field names*
into `brightdata scraper heal` — it never heals blind.

---

## Running it

```bash
cp .env.example .env        # fill in Port creds, Bright Data key, collector IDs
./scripts/apply-blueprints.sh   # 13 blueprints, idempotent, dependency-ordered
./scripts/verify.sh             # 15 preflight checks
set -a && . ./.env && set +a
node factory/run.js --brief "Route the Downtown tomato shortage"
```

---

## Honest notes

- **SigNoz is self-hosted**, so it cannot webhook *into* a local factory without a
  tunnel. The orchestrator reads alert state rather than receiving a push. Observability
  still triggers the factory; the transport is a poll.
- **The 56.25% menu null-rate is evidence, not something the demo fixes.** Re-scraping
  real restaurant menus was attempted and failed: every candidate renders prices in JS
  behind a location picker, which is exactly why the original pipeline left them null.
  The *live* contract runs on the supplier feed, which does break and heal.
- **`fsis.usda.gov` is blocked** by Bright Data ("Domain not allowed").
- **The loop closes end to end** — break → detect → gate → heal → re-verify → release,
  proven on `c_mirror` (null-rate 100% → 0%). Two earlier attempts failed for the same
  reason: the CLI's 600s timeout is **client-side only**, so Bright Data kept refactoring
  server-side and the retry was rejected with `409 Another refactor job is still in
  progress`. Once that cleared, the identical call succeeded. If you hit a 409, wait
  rather than sharpening the prompt.
- **`heal` rewrites the collector, so the "broken" and "working" page states invert
  after every repair.** As of the last heal, `span[data-amount]` is the *working*
  baseline and plain `$109.00` text is the *break*. `./scripts/break-mirror.sh --reset`
  is therefore currently the break. Check with `./scripts/verify.sh` before rehearsing.
- **The SigNoz dashboard imports through the UI**, not a script: v0.138.0 has no
  unauthenticated dashboard API and its JWT login route is unreachable. See
  `signoz/README.md`.
- Port's built-in `service` blueprint was accidentally reshaped early on; ours is
  namespaced `factory_service` and the apply script now refuses to touch blueprints it
  did not create.

## Layout

| Path | What |
|---|---|
| `factory/` | the factory: stages, Port client, domain model, heal driver |
| `app/` | Mise OS: the generated rehearsal, endpoints, background worker |
| `port/blueprints/` | 13 blueprints — pipeline + goals/decisions/risks/services |
| `mirror/` | the supplier page, and the deterministic break harness |
| `data/` | vendored Mise menu intel, baselines, live feed, current dispatch |
| `docs/` | [DEMO.md](docs/DEMO.md) · [BUILD-PLAN.md](docs/BUILD-PLAN.md) · [CONTRACTS.md](docs/CONTRACTS.md) · [incident-to-fix.md](docs/incident-to-fix.md) |
