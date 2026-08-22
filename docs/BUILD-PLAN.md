# Build plan — Mise OS factory

**Budget: ~3 hours total.** Prototype first, then iterate. Slice 1 is done; slices 2 and
3 are designed to run **in parallel by different agents** because they own disjoint files.

Read `docs/CONTRACTS.md` before starting any slice. It defines the interfaces between
slices — if you honour those, parallel work composes without coordination.

---

## Status board

Update the status cell in this table when you pick up or finish a slice. This file is
the single source of truth for who is doing what.

| Slice | Owns (exclusive) | Depends on | Status |
|---|---|---|---|
| **1. Factory core** | `factory/` | — | ✅ **DONE** |
| **2. Mise OS app** | `app/` | contract C1, C2 | ⬜ not started |
| **3. Heal loop** | `factory/heal.js`, `scripts/break-mirror.sh`, `mirror/` | contract C3, C4 | ⬜ not started |
| **4. Dashboard + docs** | `README.md`, `docs/`, SigNoz dashboard | C5 | ⬜ not started |

**Known dead ends — do not retry:**
- `fsis.usda.gov` — Bright Data rejects it, "Domain not allowed"
- `maggianos.com` menu — collector create failed (`c_mt4u57bdmex2k7x9e`, half-built).
  All candidate restaurant menus render prices in JS behind a location picker. This is
  why the original pipeline left 72 prices null. The 56.25% figure is evidence, not a
  number the demo drives down. See contract C3.

**Nobody edits a file another slice owns.** If you need a change in someone else's file,
add it to "Cross-slice requests" at the bottom instead of editing.

---

## Slice 1 — Factory core ✅ DONE

`brief|incident -> plan -> build -> verify -> approve -> release -> audit`, every stage
one OTel span under a single `factory.run` root and one Port entity carrying `trace_id`.

Verified: 7 spans in SigNoz, 4 entities in Port, release correctly blocked when the data
contract fails. Both entry points work.

```bash
cd factory && set -a && . ../.env && set +a
node run.js --brief "Route the Downtown tomato shortage"
node run.js --incident data_source_broken
```

---

## Slice 2 — Mise OS app  ⬜

**Goal.** The thing being operated on. Deliberately thin: it exists to have endpoints,
a background job, and a visible failure mode. **Resist every feature beyond this list.**

**Owns:** `app/` only.

**Build:**
- `GET /api/dispatch` — serves the current routing decision from `data/dispatch.json`
- `GET /api/health` — data freshness + last null-rate from `data/verification.json`
- `POST /api/dispatch/:id/decision` — human accept/reject; flips the Port `plan`
  entity's `approval_status` (see contract C2)
- Background worker on an interval: runs the Bright Data mirror collector, writes
  `data/supplier-feed.json`, emits its own span + metrics
- One page: the three routed tasks with their executor badges (robot / human / agent),
  the $53.30 summary, freshness timestamp, and Accept / Reject buttons

**Why the endpoint + worker pair is mandatory:** the SigNoz track is judged on "metric
tracking across **data endpoints and background jobs**". Stage spans alone do not
satisfy it. Instrument both with `factory/telemetry.js` — never `console.log`.

**Done when:**
```bash
curl -s localhost:3000/api/health | jq .           # returns freshness + null_rate
curl -s localhost:3000/api/dispatch | jq '.tasks'  # 3 tasks, 3 executors
# and a span named http.server + worker.scrape appears in SigNoz
```

---

## Slice 3 — Heal loop  ⬜  ← the differentiator

**Goal.** Close the loop: a source page changes, observability notices, the factory
opens an incident, Bright Data repairs it, a human approves, re-verify goes green.
**If time runs out anywhere else, it runs out here last.** Almost nobody builds this edge.

**Owns:** `factory/heal.js`, `scripts/break-mirror.sh`, `mirror/`.

**Build:**
- `scripts/break-mirror.sh` — rewrites `mirror/index.html` so the price markup changes
  (wrap prices in a different element / rename the class), commits, pushes. GitHub Pages
  republishes. This is the "site changed its HTML" event, made reproducible.
- `factory/heal.js` — given failing fields, calls
  `brightdata scraper heal $SCRAPER_MIRROR_COLLECTOR_ID "<concrete failing fields>"`
  then `scraper approve`. **Never heal blind** — always pass the actual failing field
  names from the verify check (rule in `CLAUDE.md`).
- Writes a `heal_event` entity in Port (`trigger`, `failing_fields`, `approver`,
  `outcome`) related to the `data_source` and the `verification` that triggered it.
- Re-run verify; null-rate returns under threshold; release unblocks.

**Done when:** `break-mirror.sh` → run factory → incident opens → heal → re-verify passes
→ a `release` entity exists, all under one trace.

---

## Slice 4 — Dashboard + docs  ⬜

**Owns:** `README.md`, `docs/`, and the SigNoz dashboard.

- **SigNoz dashboard, 4 panels only**, built to answer "what broke?" in under 30
  seconds, because "how quickly a judge could diagnose a failure from your dashboards
  alone" is a stated criterion: stage latency p50/p95, scrape throughput + freshness,
  error rate by stage, and `menu.price_null_rate` with the threshold drawn on it.
- **README**: what was built, the 56.25% -> X% null-rate story, how to run it, and an
  honest note that SigNoz is self-hosted so the orchestrator polls alert state rather
  than receiving a webhook.
- **Demo video beats** are in `docs/incident-to-fix.md`.

---

## Cross-slice requests

Add a bullet here instead of editing another slice's files.

- _(none yet)_
