# Session handoff — 2026-08-22

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
- `scripts/verify.sh` preflight runs and correctly reports 4 pass / 5 fail (the 5 are the
  missing accounts below)

## Blocked on the user — all browser OAuth, ~20 min total

- [ ] Port account (note region!) → then `./scripts/setup-port-mcp.sh` + OAuth in `claude`
- [ ] `brightdata login` → then `./scripts/setup-brightdata.sh`
- [ ] SigNoz Cloud account → ingestion key + region into `.env`

## Open decision blocking downstream work

**EU or US region.** Locks the Port MCP URL (`mcp.port.io` vs `mcp.us.port.io`) *and* the
SigNoz endpoint (`ingest.<region>.signoz.cloud`). Pick once, put in `.env`, and it flows
through `scripts/setup-port-mcp.sh` via `$REGION`.

## Biggest schedule risk

`brightdata scraper create` takes **5–25 minutes**. Create the real collector the night
before the event and commit the ID to `CLAUDE.md`. Never on the demo critical path.

## Next actions, in order

1. Pick region → `cp .env.example .env`, fill it in
2. Run the two setup scripts, get `verify.sh` to 9/9
3. Prototype the Port loop with a *stub* app: blueprints → one action → one automation →
   one approval gate → one scorecard → one dashboard. Prove brief→release works empty
   before any real app exists.
4. Build the SigNoz alert → Port automation → `scraper heal` edge. This is the loop-closing
   piece and the thing most teams will skip.
5. Only then choose and build the app.

## Still undecided

- What app the factory builds. Pick something with an obvious required field whose
  disappearance is *visually* obvious when the scraper breaks (a price, a score, a count).
- Team + repo hosting — this repo is local-only, no remote yet.
