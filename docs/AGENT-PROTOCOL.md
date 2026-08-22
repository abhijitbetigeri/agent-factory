# Working in parallel

Several agents build this at once. The rules exist because the failure mode is not
"an agent writes bad code", it is "two agents edit the same file and silently lose work".

## 1. Claim a slice before you touch anything

Open `docs/BUILD-PLAN.md`, find an unclaimed slice, set its Status to
`🔨 in progress (<your name>)`, commit **that line alone**, push. If the push is
rejected, someone claimed it first — pull and pick another.

## 2. Only edit files your slice owns

The ownership column in `docs/BUILD-PLAN.md` is exclusive. Need something changed in
another slice's files? Add a bullet under **Cross-slice requests** and keep going with
your own work. Do not "just quickly fix" someone else's file.

Shared, append-only: `data/` (each slice writes its own filenames — see contracts).
Shared, nobody edits without a request: `CLAUDE.md`, `.env`, `port/blueprints/`.

## 3. Code against `docs/CONTRACTS.md`, not against other slices' code

If the contract says `data/dispatch.json` has a `tasks[].executor` field, build against
that. Do not read another slice's source to infer behaviour — that couples you to code
that is being rewritten under you.

## 4. Pull before you push, always

```bash
git pull --rebase origin main && git push origin main
```

Commit in small pieces. A slice that lands in five commits is recoverable; one that
lands in a single 800-line commit is not.

## 5. Verify against the real systems, not against your assumptions

Every slice has a "Done when" block with a runnable check. Run it. Port and SigNoz are
both live — an entity that did not land or a span that did not export is not done.

```bash
./scripts/verify.sh          # 15 checks, must stay green
```

## 6. Report honestly

If something is half-built, say so in the status board. A slice marked done that is not
done costs more than an unclaimed slice, because the next agent builds on top of it.
