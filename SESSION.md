# Session handoff — 2026-08-22

## ⏭️ START HERE (written at the end of session 2)

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

**The use case is still undecided** — see `docs/idea-options.md`. It gates only
`brightdata scraper create` (5-25 min), which is the schedule long pole.


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

## Blocked on the user — all browser OAuth, ~20 min total

- [ ] Port account (**US region**) → then `./scripts/setup-port-mcp.sh` + OAuth in `claude`
- [ ] `brightdata login` → then `./scripts/setup-brightdata.sh`
- [ ] SigNoz Cloud account (**US region**) → ingestion key into `.env`

## Region — DECIDED 2026-08-22: US

Pinned in `CLAUDE.md` and `.env`. `PORT_MCP_URL=https://mcp.us.port.io/v1`, SigNoz
`ingest.us.signoz.cloud`. Both accounts must be created in the US region to match.
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
