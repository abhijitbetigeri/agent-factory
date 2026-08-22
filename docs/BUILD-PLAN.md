# Build plan — Mise OS factory

**Budget: ~3 hours total.** Prototype first, then iterate. Slice 1 is done; slices 2 and
3 are designed to run **in parallel by different agents** because they own disjoint files.

Read `docs/CONTRACTS.md` before starting any slice. It defines the interfaces between
slices — if you honour those, parallel work composes without coordination.

---

## Status board

Update the status cell in this table when you pick up or finish a slice. This file is
the single source of truth for who is doing what.

Priority order is **3 → 2 → 4**, not numeric order. Slice 3 is the submission; slice 2
is the pitch; slice 4 is evidence. If time runs out, it runs out on slice 4.

| Slice | Owns (exclusive) | Depends on | Priority | Status |
|---|---|---|---|---|
| **1. Factory core** | `factory/` | — | — | ✅ **DONE** |
| **3. Heal loop** | `factory/heal.js`, `scripts/break-mirror.sh`, `mirror/` | C3, C4 | **1st** | ⬜ not started |
| **2. Sim + approval** | `app/` | C1, C2 | **2nd** | ⬜ not started |
| **4. Dashboard + README** | `README.md`, `docs/`, SigNoz dashboard | C5 | 3rd | ⬜ not started |

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

## Slice 2 — Runtime-generated sim + approval gate  ⬜  ← the pitch

**The claim, stated precisely so it survives scrutiny.** The simulation is **not** a
pre-recorded demo. It is generated from `data/dispatch.json` — the dispatch the factory
just produced. A different shortage produces a different sim: different donor branch,
different crate, different path, different handoff. **The human approves by watching
the rehearsal of the physical action, not by reading a JSON diff.** The approved plan
is what would deploy to the physical robot.

Be careful with wording in the README and video: the *shipped Unity SCIM sim* is a
pre-built artifact and cannot be generated at runtime. What is generated at runtime is
**this preview**, from the dispatch. The Unity sim is the execution environment being
rehearsed *for*, and is linked as such. Do not claim Unity scenes are synthesised live.

**Owns:** `app/` only.

**Build:**
- **Sim view generated from the dispatch** — top-down branch layout, the donor branch
  (Marina, 2 days to expiry), the recipient (Downtown, 36 short), the robot path
  between them, the crate pick, and the handoff at the service pass. SVG or canvas,
  animated, driven entirely by `dispatch.json` fields. No hardcoded scenario.
- **Approve / Reject on that view.** Clicking writes to Port: flips
  `plan-<RUN>.approval_status` and sets `approved_by` (contract C2). This IS the human
  gate — approval is granted against a rehearsal, which is the whole argument for why
  a gate belongs here at all.
- `GET /api/dispatch` — serves `data/dispatch.json`
- `GET /api/health` — freshness + last null-rate
- **Background worker** on an interval: runs the Bright Data mirror collector, writes
  `data/supplier-feed.json`, emits its own span + metrics
- Link out to the shipped Unity SCIM sim as the physical execution environment

**Why the endpoint + worker pair is mandatory:** the SigNoz track is judged on "metric
tracking across **data endpoints and background jobs**". Stage spans alone do not
satisfy it. Instrument both with `factory/telemetry.js` — never `console.log`.

**Done when:**
```bash
curl -s localhost:3000/api/health | jq .           # freshness + null_rate
curl -s localhost:3000/api/dispatch | jq '.tasks'  # 3 tasks, 3 executors
# the sim renders Marina -> Downtown from dispatch.json, not from hardcoded values
# Approve flips plan-<RUN>.approval_status in Port
# spans http.server.* and worker.scrape appear in SigNoz
```

**Proof it is runtime-generated:** edit the branch numbers in `factory/mise.js`, re-run
the factory, reload — the sim must show a different donor and quantity. If it does not,
it is a hardcoded demo and the pitch is false.

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
- **Demo video beats** are in `docs/DEMO.md` — the fixed shot list. Build to it.

---

## Cross-slice requests

Add a bullet here instead of editing another slice's files.

- _(none yet)_
