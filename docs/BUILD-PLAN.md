# Build plan — Mise OS factory

**Budget: ~3 hours total.** Prototype first, then iterate. Slice 1 is done; slices 2 and
3 are designed to run **in parallel by different agents** because they own disjoint files.

Read `docs/CONTRACTS.md` before starting any slice. It defines the interfaces between
slices — if you honour those, parallel work composes without coordination.

---

## Status board

Update the status cell in this table when you pick up or finish a slice. This file is
the single source of truth for who is doing what.

Priority order is **3 → 2 → 4 → 5**, not numeric order. Slice 3 is the submission; slice 2
is the pitch; slice 4 is evidence. If time runs out, it runs out on slice 5, then slice 4.
Slice 5 is the only slice that maps to **no judged criterion** — it is a sharing surface,
not points. Never start it while 3, 2 or 4 are open.

| Slice | Owns (exclusive) | Depends on | Priority | Status |
|---|---|---|---|---|
| **1. Factory core** | `factory/` | — | — | ✅ **DONE** |
| **3. Heal loop** | `factory/heal.js`, `scripts/break-mirror.sh`, `mirror/` | C3, C4 | **1st** | 🟡 **PARTIAL** — break + detect proven live; heal on c_mirror blocked by BD `409 refactor in progress`. Repair itself proven on c_real. |
| **2. Sim + approval** | `app/` | C1, C2 | **2nd** | ✅ **DONE** — verified: endpoints, approve→Port (`approved_by: human (via simulation rehearsal)`), falsifiability check passed |
| **4. Dashboard + README** | `README.md`, `docs/`, SigNoz dashboard | C5 | 3rd | 🟡 **PARTIAL** — README + DEMO.md done; **SigNoz dashboard NOT built** (Beat 4 films the raw trace view instead) |
| **5. Landing page** | `site/` | C1 | 4th (unscored) | ⬜ not started |

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

## Slice 5 — Landing page  ⬜  ← sharing surface, not points

**What it is.** A public front page for the submission — the thing you paste into a
Discord/X/DM where a README link is too dry and the 4:30 video is too long. It is *not*
part of the demo: `docs/DEMO.md` is a fixed shot list with no web-page beat, and
`docs/plan-12h.md` commits to "zero web UI in the video". Do not add a beat for this.

**Be honest about its value.** No track criterion in `CLAUDE.md` rewards a landing page.
It wins nothing. It exists so the work is shareable after the deadline. That is why it
sits below slice 4 and gets cut first.

**Owns:** `site/` only. New path — collides with nothing, so it can run in parallel.

**Tech stack — match `app/` exactly.** Slice 2 already set the house style; do not
introduce a second one:
- Plain static HTML. **No framework, no build step, no bundler, no CDN, no npm deps.**
- One self-contained `site/index.html`: inline `<style>` and inline `<script>`, the way
  `app/public/index.html` is built.
- **Reuse the exact palette** via CSS custom properties on `:root`, copied verbatim from
  `app/public/index.html:4-5` so the two pages look like one product:
  `--bg:#0d1117 --panel:#161b22 --line:#30363d --fg:#e6edf3 --dim:#8b949e`
  and the executor colours `--robot:#58a6ff --human:#d29922 --agent:#3fb950 --bad:#f85149`.
- **Inline SVG** for any diagram, as the sim does — no image files, no icon fonts.
- Vanilla `fetch` only if it needs data at all. Prefer none: see "static by default".

**Static by default — this is the important constraint.** The landing page must render
with the factory switched off. `app/` needs a live Node process, a running SigNoz on
:4318 and Port credentials; a landing page that depends on any of those is broken for
every reader who is not you. Bake the numbers in as text at build time. If it must show
live data, fetch `/api/health` defensively and degrade to the baked figure on failure —
never render an error or an empty panel to a stranger.

**Content — pull from what already exists, invent nothing:**
- The claim: the factory is the deliverable, not the app it produces.
- The loop, as a diagram: `brief|incident → plan → build → verify → approve → release → audit`.
- The heal story: source HTML changes → null-rate breaches → incident → Bright Data
  heals → human approves → re-verify green. This is the differentiator; lead with it.
- The honest numbers, including the ones that did not go well: the 56.25% menu null-rate
  is *evidence of a real defect*, not a metric the demo drives down (contract C3).
- Links out: repo, the 4:30 video, and the shipped Unity SCIM sim.
- ⚠️ Same wording discipline as slice 2: the Unity sim is **pre-built**. Only the
  rehearsal preview is runtime-generated. Do not let marketing voice blur that.

**⚠️ The one real collision risk — GitHub Pages.** Slice 3 publishes `mirror/` to Pages
and `break-mirror.sh` pushes to it on purpose. Slice 5 shares that deployment even though
it shares no files:
- Serve the landing page at the Pages **root**, mirror stays at `/mirror/`. Never move,
  rename or reconfigure `mirror/` — slice 3 owns it and a pinned collector points at it.
- Do not add a Pages workflow that rebuilds or wipes the site root on push, or the next
  `break-mirror.sh` run silently breaks the heal demo.
- If Pages config needs changing, that is a **cross-slice request**, not an edit.

**Done when:**
```bash
open site/index.html          # renders fully with no server, no factory, no network
```
- Readable at 375px wide and at 1440px.
- Zero requests to any external host (no CDN, no font host, no analytics).
- Palette matches `app/public/index.html` side by side.
- `mirror/` untouched: `git status` shows no change under `mirror/`.

---

## Cross-slice requests

Add a bullet here instead of editing another slice's files.

- **The four workspace blueprints are empty and no slice owns filling them.**
  Verified 2026-08-22 against the live US org: pipeline blueprints populate correctly
  (`brief`/`plan`/`build_run`/`verification`/`agent_invocation` at 5 each, `release` and
  `incident` at 1, `trace_id` on every one), but `goal`, `technical_decision`, `risk`
  and `factory_service` are all at **0**. `factory/run.js` never writes them, C2 does not
  list them, and no slice claims them — so on current trajectory they ship empty.

  This is not cosmetic. `CLAUDE.md` records the Port track criterion as literally
  "project goals, technical choices, risk factors, and cataloged services", and that
  *"an empty workspace loses this prize"*. Four empty blueprints is a visible zero on a
  judged criterion, not a missing nice-to-have.

  **Do not fold this into slice 4.** Slice 4 is explicitly the one that gets cut if time
  runs out; attaching a scored criterion to the droppable slice is how it gets lost.

  **Proposed shape — deliberately conflict-free, so it can run in parallel with 2 and 3:**
  - New exclusive path `port/workspace/*.json` + `scripts/seed-workspace.sh`. Touches no
    file any slice owns, so it needs no coordination and cannot cause a merge conflict.
  - Seed from decisions this repo has *already made* rather than inventing content —
    they are sitting in `SESSION.md` and `CLAUDE.md` and just need entity form:
    - `technical_decision` — US region over EU; self-hosted SigNoz over Cloud; the
      mirror-collector harness; polling alert state instead of webhooks.
    - `risk` — `scraper create` takes 5-25 min and cannot sit on the demo critical path;
      menu prices render in JS behind a location picker (the 56.25% null-rate defect);
      Docker Desktop does not auto-start, so the stack is down after any reboot.
    - `goal` — the factory is the deliverable, not the app it produces; a judge must be
      able to diagnose a failure from the dashboard in under 30 seconds.
    - `factory_service` — the catalog: `factory-orchestrator`, the slice-2 app and its
      background scrape worker, the SigNoz stack, the Bright Data collector.
  - Relate them where the blueprint schemas already allow it (`brief.targets_goal` is
    live and currently `[]` on every brief), so the workspace connects to the pipeline
    instead of sitting beside it as decoration.

  **Done when:** all four blueprints are non-empty in the US org, at least one `brief`
  has a non-empty `targets_goal`, and re-running `seed-workspace.sh` is idempotent
  (it upserts, so a second run must not duplicate).

- **`incident` blueprint is live-only and not version-controlled.** It exists in the org
  (HTTP 200, 1 entity) and `factory/run.js:84` writes to it, but there is no
  `port/blueprints/incident.json`. `apply-blueprints.sh` rebuilding from files into a
  fresh org would therefore omit it and the incident path would 404 at runtime. Export
  it to a file alongside the other 12. Low effort, and it only bites during a rebuild —
  which is exactly when there is no time to debug it.
