# The demo — UI-driven shot list

**4:30 target, 5:00 hard cap.** Everything is driven from the browser. No terminal after setup.

The four things the brief asks to see are marked ⬥ — **workflow**, **Port dashboard**,
**live SigNoz**, **Bright Data auto-fix**.

---

## Setup, before you roll

```bash
cd ~/projects/agentic-factory
set -a && . ./.env && set +a
./scripts/verify.sh          # must be 16/16
node app/server.js           # leave running
```

Then open, in tabs:

| Tab | URL |
|---|---|
| **Console** | http://localhost:3000/console |
| Landing page | http://localhost:3000/ |
| Port | https://app.us.port.io |
| SigNoz | http://localhost:8080 |

Import the dashboard once: `./scripts/import-dashboard.sh`, then paste the JSON at
SigNoz → Dashboards → Import.

**Check which side of the break you are on.** The console's feed pill reads *feed
healthy* or *feed degraded*. You want **healthy** before you start. `heal` rewrites the
collector each time it runs, so which page state counts as "broken" flips after every
repair — trust the pill, not the button labels.

---

## Beat 0 · 0:00–0:35 · The premise ⬥ workflow

**Console → panel 00, Market intelligence.**

16 restaurants, 53 branches, 128 dishes, 297 ingredients — and a row of red bars.

> "Every routing decision this system makes is arithmetic over this data. It came from a
> scraping pipeline that failed silently on prices. Chinese, Indian, Italian, Mexican —
> every price missing. 56% of the dataset is blind, and nothing was watching it. No data
> contract, no metric, no alert."

The bars do the work here. Do not read the number out; point at the red.

---

## Beat 1 · 0:35–1:20 · The factory runs, and refuses ⬥ workflow

**Panel 01 → Submit brief.** Stages stream into the page.

```
brief · plan · build · verify · approve
Transfer 10kg, buy net 26kg @ $2.05 = $53.3
  [robot] transfer: 10kg from Marina (expires in 2d, use first)
  [human] handoff: Crate handed to the cook at the service pass
  [agent] procure: Only the NET shortage is bought: 26kg @ $2.05/kg
release SKIPPED
```

> "One brief. The factory read the catalog, and routed the work across an agent, a robot
> and a human. Surplus moves before anything is bought, nearest-expiry first, and only
> the net shortage reaches procurement. Then it stopped — because release is gated."

`verify` takes ~10s on a live scrape. Talk over it; that pause is the factory checking
its data contract before it commits to anything.

---

## Beat 2 · 1:20–2:05 · Approve the rehearsal ⬥ workflow

**Panel 02.** The simulation, drawn from the dispatch that just ran.

> "You do not approve a JSON diff. This is generated from the dispatch — this donor
> branch, this crate, two days from expiry, this handoff at the service pass. A
> different shortage draws a different picture. The human watches what the robot will
> do, and approves *that*."

Click **Approve dispatch** → `plan-<RUN> → approved in Port`.

**If challenged on "generated":** change the branch numbers in `factory/mise.js`, re-run,
and the drawing changes. Same code, different dispatch.

---

## Beat 3 · 2:05–2:40 · Port ⬥ Port dashboard

Entity graph: `incident → brief → plan → build_run → verification → release`. Then the
catalog — goals, technical decisions, risks, services. Show the plan you just approved.

> "Every stage of that run is an entity, and every entity carries the trace id. This is
> not a log of what happened. It is the graph of what happened, and why."

---

## Beat 4 · 2:40–3:10 · SigNoz ⬥ live SigNoz

One trace, the stage spans, `stage.verify` in red. Click a log line and land on its span.
Then the dashboard: null-rate with the threshold drawn on it, stage latency, throughput.

> "One trace, every stage. Logs correlated to spans, so a log line takes you to the stage
> that produced it. And that red span is the sensor the next part hangs off."

---

## Beat 5 · 3:10–4:10 · The loop ⬥ Bright Data auto-fix ← **the submission**

**Panel 03, in order:**

1. **Change the source page** → the supplier site's HTML changes, for real, via a commit
2. Wait ~90s for GitHub Pages *(cut here, or narrate)*
3. **Re-scrape now** → `parse_error: value must be finite number`, contract **breached**
4. **Trigger incident** (panel 01) → null-rate 100%, failing fields `name, price`,
   **release SKIPPED**
5. **Repair with Bright Data** → `null-rate 100.0% → 0.0% RECOVERED`
6. **Trigger incident** again → **PASS**, release created

> "The source page changed its HTML — a real commit, not a mock. Our check caught it, not
> Bright Data's: Bright Data never decides a scraper is broken, that is our job. The
> factory named the failing fields, opened an incident, and asked a human. Bright Data
> rewrote the collector against the page's new structure. Re-verified, released."

**If anything gets cut, this is cut last.**

---

## Beat 6 · 4:10–4:30 · Run it again

Type a brief nobody rehearsed into panel 01 and run it live.

> "If it only works on the rehearsed brief, it is a prompt, not a factory."

---

## Cut order

1. Beat 4's dashboard → raw trace view alone tells the story
2. Beat 0 → fold the 56% into Beat 1's voiceover
3. Beat 6 → keep if at all possible, judges explicitly test for it

**Never cut:** Beats 1, 2, 5.

---

## Known rough edges — say them rather than hide them

- **SigNoz is self-hosted**, so it cannot webhook into a local factory without a tunnel.
  The orchestrator reads alert state instead of receiving a push.
- **The 56.25% menu null-rate is evidence, not something the demo fixes.** Re-scraping
  real restaurant menus was attempted and failed — every candidate renders prices in JS
  behind a location picker, which is exactly why they were null to begin with. The live
  contract runs on the supplier feed, which does break and heal.
- **A `409` from Bright Data means a refactor job is still running.** Wait; do not
  sharpen the prompt. The CLI's 600s timeout is client-side only.
