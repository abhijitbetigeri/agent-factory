# The deployed exhibit

This directory is what Vercel serves. It is a **static exhibit**, not the running system.

## Why it cannot be the running system

The console drives the factory by spawning processes. None of that survives a
serverless runtime:

| Console action | What it really does | Why Vercel cannot |
|---|---|---|
| Submit brief / Trigger incident | spawns `node factory/run.js` | serverless cannot spawn CLIs |
| Repair with Bright Data | spawns `npx brightdata scraper heal` | same, and it takes 5–15 min vs a 60s function limit |
| Change the source page | `bash scripts/break-mirror.sh`, which does `git commit && git push` | no repo or credentials in the runtime |
| Any run | writes `data/dispatch.json`, `data/supplier-feed.json` | filesystem is read-only |
| Any run | exports OTel to `localhost:4318` | self-hosted SigNoz is unreachable from Vercel |

## What it is instead

The same UI, replaying **transcripts recorded against the live system**. Every line in
`snapshots/*.txt` is real output from a real run — including the failing one, where the
collector reports `parse_error: Parse error: value must be finite number`, and the heal
that took it from 100% null back to 0%.

`snapshots/market.json` and `snapshots/dispatch.json` are generated from the real
dataset and a real factory run, not hand-written.

The banner at the top of the console says all of this to anyone who opens it.

## Regenerating the snapshots

```bash
set -a && . ./.env && set +a
node factory/run.js --brief "Route the Downtown tomato shortage" | grep -v '^\[otel\]' > web/snapshots/run-brief.txt
cp data/dispatch.json web/snapshots/dispatch.json
curl -s localhost:3000/api/market > web/snapshots/market.json   # with the app running
```
