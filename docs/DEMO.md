# The demo — fixed shot list

**4:30 target, 5:00 hard cap.** This is settled. Build to it; do not add beats.

The four things the brief asks to see are marked ⬥ — **terminal workflow**, **Port
dashboard**, **live SigNoz**, **Bright Data auto-fix**. All four must survive any cut.

Status legend: ✅ works today · ⬜ needs the named slice

---

## Beat 0 · 0:00–0:25 · The premise ✅

**On screen:** `data/baseline-null-rate.json`.

> "Mise is a real supply chain system — it won a hackathon. It routes food between
> restaurant branches. And 72 of its 128 dish prices are null. It has been routing on
> data that is 56% blind, and nobody knew, because nothing was watching."

Sets up all three sponsors at once: something to fix (Bright Data), something to govern
(Port), something that should have caught it (SigNoz).

---

## Beat 1 · 0:25–1:10 · The factory runs, and refuses ⬥ terminal ✅

```bash
node factory/run.js --brief "Route the Downtown tomato shortage"
```

**On screen:** stages streaming, then the routing decision and the refusal.

```
  brief · plan · build · verify · approve
  Transfer 10kg, buy net 26kg @ $2.05 = $53.3
    [robot] transfer: 10kg from Marina (expires in 2d, use first)
    [human] handoff: Crate handed to the cook at the service pass
    [agent] procure: Only the NET shortage is bought: 26kg @ $2.05/kg
  release SKIPPED (contract failed)
```

> "The factory took a brief, read the catalog, and routed the work across an agent, a
> robot, and a human. Then it refused to release — because it will not dispatch a robot
> on data it knows is blind. That refusal is the governance working."

---

## Beat 2 · 1:10–2:00 · Approve the rehearsal, not the diff ⬜ slice 2

**On screen:** the sim, generated from `dispatch.json`. Marina → Downtown, the crate
with 2 days to expiry, the robot path, the handoff at the service pass. Then Approve.

> "You do not approve a JSON diff. The factory generated this simulation from the
> dispatch it just produced — this donor branch, this crate, this path. A different
> shortage generates a different simulation. The human watches what the robot will do,
> and approves *that*. The same plan is what deploys to the physical robot."

**Wording discipline:** the shipped Unity SCIM sim is pre-built. What is generated at
runtime is **this preview, from the dispatch**. Link the Unity sim as the physical
execution environment being rehearsed for. Never claim Unity scenes are synthesised live.

Clicking Approve flips `plan-<RUN>.approval_status` in Port — visible in Beat 3.

---

## Beat 3 · 2:00–2:35 · Port ⬥ Port dashboard ✅

**On screen:** the entity graph — `incident → brief → plan → build_run → verification`
— then the catalog: goals, technical decisions, risks, services.

> "Every stage of that run is an entity here, and every entity carries the trace id.
> This is not a log of what happened; it is the graph of what happened and why."

Show the plan flipping to `approved` from Beat 2.

---

## Beat 4 · 2:35–3:05 · SigNoz ⬥ live SigNoz ⬜ dashboard, slice 4

**On screen:** one trace, seven stage spans, `stage.verify` red —
`null-rate 0.5625 > 0.05`. Click a log line, jump to its span. Then the dashboard:
null-rate with the threshold drawn on it, stage latency, error rate.

> "One trace, every stage. The logs are correlated to the spans, so a log line takes you
> to the exact stage that produced it. And that red span is the sensor the next beat
> hangs off."

---

## Beat 5 · 3:05–4:05 · The loop ⬥ Bright Data auto-fix ⬜ slice 3 ← **the submission**

```bash
./scripts/break-mirror.sh      # commits a real HTML change to the source page
```

**The full loop is proven end to end on one collector.** Sequence, all live:

```
./scripts/break-mirror.sh                      # real commit, price markup restructured
node factory/run.js --incident data_source_broken
    collector error: parse_error: Parse error: value must be finite number
    supplier null-rate 100.0%  -> FAIL   failing fields: name, price
    release SKIPPED (contract failed)
node factory/heal.js                           # human gate, then repair
    null-rate 100.0% -> 0.0%  RECOVERED
node factory/run.js --incident data_source_broken
    supplier null-rate 0.0% -> PASS
    release    324ms                           # release entity created
```

In Port afterwards: `heal_event.outcome = resolved`, `data_source.health = healthy`,
and a new `release`. In SigNoz: `stage.verify` red on the failing run, green on the
recovering one, both under their own `factory.run` traces.

**⚠️ Read before recording — the states are INVERTED.** `heal` rewrote the collector to
read the new markup, so as of the last heal:

| Page state | Collector | Command to get there |
|---|---|---|
| `<span data-amount="109.00">` | ✅ works — **start here** | `./scripts/break-mirror.sh` |
| `$109.00` text | ❌ breaks, `parse_error` | `./scripts/break-mirror.sh --reset` |

**`--reset` is now the break.** Confirmed by test, not assumed. Roll from the
data-amount state and run `--reset` on camera. If you heal again, expect the pair to
invert again — the collector always adapts to whatever it was last healed against.
`./scripts/verify.sh` tells you which side you are on in one command.

> "The source page changed its HTML — a real commit, not a mock. SigNoz caught it. Port
> opened an incident and asked a human. Bright Data repaired the scraper itself. The
> factory re-verified and released. Observability detected, governance decided, the data
> layer repaired itself — and a human stayed in control of all of it."

**If anything gets cut, this is cut last.** Almost nobody builds this edge.

---

## Beat 6 · 4:05–4:25 · Run it again ✅

A brief nobody rehearsed, live.

> "If it only works on the rehearsed brief, it is a prompt, not a factory."

---

## Close · 4:25–4:30

The loop diagram. One sentence: **the app is the test run; the factory is the deliverable.**

---

## Cut order, if the clock beats us

1. Beat 6 (run it again) — keep if at all possible, judges explicitly test for it
2. Beat 4's dashboard → show the raw trace view instead
3. Beat 0 → fold the 56% line into Beat 1's voiceover

**Never cut:** Beat 1, Beat 2, Beat 5. Those are the terminal workflow, the pitch, and
the auto-fix.

---

## Pre-record checklist

```bash
./scripts/verify.sh                  # must be 15/15
docker ps | grep signoz              # ingester healthy, OTLP 4318 answering
git status --short                   # clean, mirror page in its UNBROKEN state
```

Reset the mirror to unbroken and re-run the factory once before recording, so Beat 5's
break is the only break on camera.
