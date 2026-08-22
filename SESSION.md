# Session handoff — 2026-08-22

## ⏭️ START HERE

**Building right now? Read `docs/BUILD-PLAN.md` first** — it has the slice status board,
who owns which files, and runnable done-criteria. Then `docs/CONTRACTS.md` for the
interfaces between slices, and `docs/AGENT-PROTOCOL.md` if more than one agent is working.

Project definition: `docs/incident-to-fix.md` (Mise OS — an operating system for
physical work in the food supply chain, and the factory that builds it).

## Earlier handoff (session 2)

**Run Claude Code from THIS directory** (`agentic-factory`), not from `~/projects`.
Session 2 was rooted at the parent dir, so `.mcp.json` here was never loaded and
`claude -c` from this repo found no history. Start with a plain `claude` in this folder.

Immediately on starting:
1. Approve the `port` MCP server when prompted (it comes from `.mcp.json`, committed here)
2. `/mcp` -> `port` -> Authenticate (browser OAuth, US region)
3. Sanity check: ask "list all blueprints in my Port org"

Then the two remaining credential chores: `PORT_CLIENT_ID`/`PORT_CLIENT_SECRET` from
Port UI -> org settings -> Credentials (app.us.getport.io) into `.env`, and
`./scripts/setup-brightdata.sh` + SigNoz key. Then `./scripts/apply-blueprints.sh`.

**⚠️ TWO Port orgs exist on this account.** We build in the **US** org
`org_ZYv2lWwJzrARBLVA` (app.us.port.io). The EU org `org_qEYkxdqqRbulG5Dj`
(app.port.io) is abandoned. Client credentials MUST be created while inside the US
org — creds from the EU org authenticate successfully and silently write to the wrong
place. `.mcp.json` already points at `mcp.us.port.io`.

**USE CASE DECIDED: #5 Incident-to-Fix Factory** — see `docs/incident-to-fix.md`.
SigNoz alert is the entry point; Port triages and gates; Bright Data both breaks
(c_mirror's page changes -> null-rate spike -> incident class #1) and repairs
(`scraper heal`) and informs (c_real scrapes upstream status during triage).
13 blueprints applied, `incident` added as the entry-point entity.


State of prep when this repo was created. A fresh Claude Code session in this directory
should read this first; project memory for this path is already seeded.

## Decisions already made (don't re-litigate)

1. **This is a new hackathon, unrelated to travel-guardian.** The `projects/antler-hack`
   repo is the June 2026 Beta Hacks x Antler project (TravelGuardian / Butterbase). Nothing
   carries over.
2. **The three sponsors form one closed loop, not three integrations.** SigNoz detects →
   Port decides (with a human gate) → Bright Data repairs → re-verify. This is the core
   differentiator; see `docs/factory-design.md`.
3. **Detection is ours to build.** Bright Data's CLI never decides a scraper is broken
   ("you are the detector"), which is why the null-rate check in `verify` and the SigNoz
   alert on `scraper.field_null_rate` are load-bearing, not decoration.
4. **The factory is the deliverable; the app is the test run.** Resist app feature creep.

## Verified working on this machine (2026-08-22)

- Node v20.20.2, npm 10.8.2, Docker 29.4.0, gh 2.95.0
- Bright Data CLI 0.3.5 via npx — confirmed `scraper create|run|heal|approve`, `add mcp`,
  `skill list` (9 skills available)
- `otel-smoke/` runs both paths: single trace ID, correct parent/child nesting, ERROR
  status propagation, `scraper.heal.requested` + `factory.escalated` span events, metrics
  tagged correctly
- `scripts/verify.sh` preflight rewritten; now **7 pass / 5 fail / 1 warn**. All 5
  failures are missing credentials (below). The 1 warning is the collector id, which is
  blocked on the use-case choice, so it warns rather than fails.
- **OTel logs signal added and verified** — `tracing.js` now exports traces + metrics +
  logs. Log records carry `traceId`/`spanId`, so a log line in SigNoz links back to the
  span that emitted it. This was a real gap: the SigNoz track criterion names all three
  signals, and we only had two. Use `log(level, body, attrs)` from `tracing.js`.
- **12 Port blueprints drafted** in `port/blueprints/` + `scripts/apply-blueprints.sh`
  (idempotent, dependency-ordered). Idea-agnostic — safe to apply the moment Port
  machine credentials exist. See `port/README.md`.

## Credentials — ALL CLEARED 2026-08-22 ✅

- [x] Port — client credentials in `.env`, `port` MCP registered
- [x] Bright Data — logged in, key in `.env`, balance $50, zones + skills + MCP done
- [x] SigNoz — **self-hosted** docker compose, not cloud. `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`

`./scripts/verify.sh` is now **13 passed / 0 failed / 1 warned**. The single warning is
`SCRAPER_REAL_COLLECTOR_ID`, gated on the use-case choice — that is the ONLY thing left.

Two bugs found and fixed while wiring this up:
1. `brightdata add mcp --project` wrote the literal API token into the **committed**
   `.claude/settings.json`. Moved to `.mcp.json` via `${BRIGHTDATA_API_KEY}`; `verify.sh`
   now fails if a literal key reappears. Never run that command again.
2. `verify.sh`'s logs check grepped stdout for `traceId`, which only the console exporter
   prints — so it passed only while SigNoz was UNconfigured. Now mode-aware and asserts
   the record actually lands in ClickHouse.

⚠️ Launch Claude Code with the env loaded or `.mcp.json` expansion yields an
unauthenticated Bright Data MCP: `set -a && . ./.env && set +a && claude`

## Region — DECIDED 2026-08-22: US

Pinned in `CLAUDE.md` and `.env`. `PORT_MCP_URL=https://mcp.us.port.io/v1`. Port US
verified live: `api.us.port.io` issues a token for `org_ZYv2lWwJzrARBLVA`, and the same
credentials 401 against the EU endpoint — so the abandoned EU org cannot be hit by accident.
SigNoz no longer follows this decision: it is **self-hosted on localhost**, so region
applies to Port only.
`.env` now exists (copied from `.env.example`); only the three secrets are still empty.

## Biggest schedule risk

`brightdata scraper create` takes **5–25 minutes**. Create the real collector the night
before the event and commit the ID to `CLAUDE.md`. Never on the demo critical path.

## Next actions, in order

1. ~~Pick region → `cp .env.example .env`~~ — done 2026-08-22 (US). Secrets still empty.
2. Run the two setup scripts, get `verify.sh` to 9/9
3. Prototype the Port loop with a *stub* app: blueprints → one action → one automation →
   one approval gate → one scorecard → one dashboard. Prove brief→release works empty
   before any real app exists.
4. Build the SigNoz alert → Port automation → `scraper heal` edge. This is the loop-closing
   piece and the thing most teams will skip.
5. Only then choose and build the app.

## Decided 2026-08-22

- **Region: US.** Pinned in `CLAUDE.md` and `.env`.
- **Budget: under 12 hours** of working time. Cuts in `docs/plan-12h.md` stand.
- **Port AI Builder is IN** (Plan mode first, then Build) — faster than hand-authoring
  12 blueprints, and explicitly rewarded by the brief.
- **Port account exists**, created by the user. MCP connection still outstanding.

## ⚠️ STILL OPEN — the use case

**The idea is NOT chosen.** `docs/plan-12h.md` was drafted against a Keychron price
tracker; that was a recommendation, not a decision. Treat every app/target detail in it
as placeholder. Options and trade-offs: `docs/idea-options.md`.

Everything currently being built is deliberately **idea-agnostic**: the OTel spine, the
Port blueprints, and the setup scripts do not depend on which of the five ideas wins.

The decision gates exactly one thing — `brightdata scraper create`, which takes 5-25 min.

## Still undecided

- Team + repo hosting — this repo is local-only, no remote yet.
