# Contracts between slices

These are the only surfaces slices share. Honour them and parallel agents compose
without talking to each other. Change one **only** by adding a note under
"Cross-slice requests" in `docs/BUILD-PLAN.md` — never unilaterally, because someone
else is coding against it right now.

---

## C1 — `data/dispatch.json`

**Written by** slice 1 (factory `build` stage). **Read by** slice 2 (app).
Rewritten on every factory run.

```jsonc
{
  "run": "run-1787430907356",
  "trace_id": "a51a8ac89799f90236e9a00885459248",  // links straight to the SigNoz trace
  "ingredient": "tomato",
  "need":  { "id": "downtown", "name": "Downtown", "onHand": 4.0, "par": 40, "gap": 36 },
  "transfers": [ { "from": "marina", "to": "downtown", "qty": 10, "expiryDays": 2 } ],
  "tasks": [
    { "kind": "transfer", "executor": "robot", "qty": 10, "from": "marina", "to": "downtown",
      "rationale": "10kg from Marina (expires in 2d, use first)" },
    { "kind": "handoff",  "executor": "human", "at": "downtown",
      "rationale": "Crate handed to the cook at the service pass" },
    { "kind": "procure",  "executor": "agent", "qty": 26, "unitPrice": 2.05, "cost": 53.3,
      "rationale": "Only the NET shortage is bought: 26kg @ $2.05/kg" }
  ],
  "buy": { "qty": 26, "unitPrice": 2.05, "cost": 53.3 },
  "risk": 4,
  "requiresHumanApproval": true,
  "summary": "Transfer 10kg, buy net 26kg @ $2.05 = $53.3"
}
```

`executor` is always one of `robot` | `human` | `agent`. The app renders a badge per task.

---

## C2 — Port entity identifiers

**Written by** slice 1 and slice 3. **Updated by** slice 2 (approval only).

Every entity carries `trace_id`. Identifiers are derived from the run id:

| Blueprint | Identifier | Notes |
|---|---|---|
| `brief` | `brief-<RUN>` | `origin` = `human` / `incident` / `scheduled` |
| `plan` | `plan-<RUN>` | `approval_status` = `pending` / `approved` / `rejected` |
| `build_run` | `build-<RUN>` | |
| `verification` | `verify-<RUN>` | carries `null_rate`, `contract_ok` |
| `release` | `rel-<RUN>` | only created when approved **and** contract passes |
| `incident` | `inc-<RUN>` | `incident_class`, `signal`, `fix_path` |
| `heal_event` | `heal-<RUN>` | slice 3 writes this |
| `agent_invocation` | `agent-<stage>-<RUN>` | |

**Slice 2's approve/reject** must PATCH only `plan-<RUN>`'s `approval_status` and
`approved_by`. Use `factory/port.js` `upsert()` — it merges, so partial updates are safe.

---

## C3 — The data contract check

**Owned by** slice 1 `verify`. **Consumed by** slice 3.

There are **two** null-rate signals. Keep them distinct — they do different jobs.

| Metric | Source | Now | Role |
|---|---|---|---|
| `menu.price_null_rate` | vendored Mise menu data | **0.5625** | the legacy defect. Why the factory exists. Static "before" evidence. |
| `supplier.price_null_rate` | `c_mirror` live scrape | 0.0 | the live contract. This is what breaks, alerts, heals, and recovers. |

- Required fields: `SCRAPER_REQUIRED_FIELDS` (`name,price`)
- Threshold: `SCRAPER_NULL_RATE_THRESHOLD` (`0.05`)
- Breach ⇒ `stage.verify` span status **ERROR**, span event `data_contract.breached`,
  `verification.status = fail`, release skipped.

**Why two.** The 56.25% menu figure is a real, measurable defect left by the old
Exa+Firecrawl+LLM pipeline, and it is what motivates the project. But we cannot drive
it down: an attempt to re-scrape real restaurant menus through Bright Data
(`maggianos.com`) **failed to build a collector**, and every candidate menu site
renders prices in JS behind a location picker — which is precisely why the original
pipeline left them null.

So the *live* contract that the heal loop exercises runs on `c_mirror`, which works,
is breakable on demand, and has proven `heal`. The menu figure stays as documented
evidence, not as something the demo claims to fix. Do not build a demo beat that
promises "56% -> 0%".

---

## C4 — Bright Data collectors

| Name | ID | Target | Role |
|---|---|---|---|
| `c_mirror` | `c_mt4sjr912k58zc0ek7` | `abhijitbetigeri.github.io/agent-factory/mirror/` | supplier feed; the deterministic break harness |
| `c_real` | `c_mt4sihtk1e4weky7id` | `githubstatus.com` | upstream status during triage |

Both IDs live in `.env` and `CLAUDE.md`. `heal` on `c_mirror` is proven working;
`c_real` was itself repaired by `scraper heal` after it initially extracted nothing.

`fsis.usda.gov` is **blocked** by Bright Data ("Domain not allowed"). Do not retry it.

---

## C5 — Telemetry names

**Everything** must use `factory/telemetry.js`. `console.log` is not observability.

| Kind | Name |
|---|---|
| root span | `factory.run` |
| stage spans | `stage.brief` `stage.incident` `stage.plan` `stage.build` `stage.verify` `stage.approve` `stage.release` `stage.audit` |
| app spans | `http.server.<route>`, `worker.scrape` |
| metric | `menu.price_null_rate` (gauge) |
| metric | `factory.stage.duration` (histogram, ms, tagged `factory.stage`) |
| span event | `data_contract.breached`, `scraper.heal.requested`, `scraper.heal.approved` |

Logs: `log(level, body, attrs)` from `telemetry.js`. Records are trace-correlated
automatically when emitted inside an active span.

---

## C6 — Environment

Everything reads `.env` (gitignored). Launch anything that needs it with:

```bash
set -a && . ./.env && set +a
```

Keys in play: `PORT_CLIENT_ID`, `PORT_CLIENT_SECRET`, `REGION=us`,
`BRIGHTDATA_API_KEY`, `SCRAPER_MIRROR_COLLECTOR_ID`, `SCRAPER_REAL_COLLECTOR_ID`,
`SCRAPER_REQUIRED_FIELDS`, `SCRAPER_NULL_RATE_THRESHOLD`,
`OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`.

Port org is **US** (`org_ZYv2lWwJzrARBLVA`). A second, abandoned EU org exists —
credentials from it authenticate fine and write to the wrong place.
