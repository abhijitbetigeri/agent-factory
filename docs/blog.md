# The scraper that fixed itself, and the 56% nobody noticed

*Building an agentic software factory with Port, Bright Data and SigNoz*

**Who this is for:** anyone wiring agents to tools that touch the real world, and anyone
whose system makes decisions from scraped data. The middle section is a working
implementation you can copy — stage instrumentation, a data contract, a self-repair loop,
and the mistakes that cost us the most time.

**Contents** · [The defect](#the-app-is-the-test-run) ·
[Three tools, one loop](#three-tools-one-loop) ·
[How it's actually built](#how-its-actually-built) ·
[Breaking it on purpose](#breaking-it-on-purpose) ·
[Four ways we got it wrong](#four-ways-we-got-it-wrong) ·
[Takeaways](#what-wed-tell-someone-starting-this-tomorrow)

---

There's a dataset in this project with 128 dishes in it, scraped from restaurant menus.
Seventy-two of them have `"price": null`.

Nothing failed to produce that. No exception was thrown, no job went red, no alert
fired. An earlier scraping pipeline — search, then a generic page scrape, then an LLM
extraction pass — ran to completion and returned a file that looked fine. More than half
the prices simply weren't in it.

That dataset feeds a supply chain system that decides how to move food between
restaurant branches. Transfer 10kg from the branch whose stock expires in two days, buy
only the net shortage at $2.05/kg. That arithmetic had been running on data that was
**56% blind**, and the only reason anyone found out is that we went looking.

This is a post about building the thing that would have caught it.

---

## The app is the test run

The hackathon brief was unusually pointed: *anyone can build a decent app in a couple of
hours now. Can you build the factory that builds the app?*

So the deliverable isn't the supply chain system. It's the factory around it — an
executable, repeatable, observable pipeline that takes a brief or an incident through
`plan → build → verify → approve → release → audit`, keeps a human in the loop where it
matters, and can survive being run again on something nobody rehearsed.

We called the app **Mise OS**: an operating system for physical work. It takes a unit of
work — a restock, an inter-branch transfer, a procurement pickup — and routes it to
whoever should execute it. An **AI agent** negotiates with suppliers. A **robot** moves
the crate. A **human** takes the handoff at the service pass.

A run produces something concrete:

```
Transfer 10kg, buy net 26kg @ $2.05 = $53.3
  [robot] transfer: 10kg from Marina (expires in 2d, use first)
  [human] handoff: Crate handed to the cook at the service pass
  [agent] procure: Only the NET shortage is bought: 26kg @ $2.05/kg
```

Surplus moves before anything is bought. A branch below its own par can't donate.
Nearest-expiry stock goes first. Only the *net* shortage reaches procurement.

And then, on that first run:

```
release SKIPPED (contract failed)
```

The factory refused to dispatch a robot on data it knew was blind. That refusal — the
governance visibly doing something rather than rubber-stamping — turned out to be the
best demo beat in the whole project, and we didn't design it. It fell out of taking the
data contract seriously.

---

## Three tools, one loop

The easy version of a three-sponsor hackathon is three integrations bolted to one app.
The interesting version is a loop where each tool does a job the other two can't.

```
SigNoz detects  →  Port decides (human in the loop)  →  Bright Data repairs  →  re-verify
      ↑                                                                              │
      └──────────────────────────────────────────────────────────────────────────────┘
```

**SigNoz is the nervous system.** Every factory stage is a span under one `factory.run`
trace. Logs are emitted inside the active span, so they carry `trace_id` and `span_id` —
a log line jumps straight to the stage that produced it. And the null-rate is a *metric*,
which means a threshold breach is an input to the system rather than something a human
reads afterwards.

**Port is the factory floor.** Thirteen blueprints: the pipeline (`brief`, `plan`,
`build_run`, `verification`, `release`, `incident`, `heal_event`, `data_source`,
`agent_invocation`) and the workspace (`goal`, `technical_decision`, `risk`,
`factory_service`). Every entity carries the run's `trace_id`, so any node in the Port
graph jumps to its SigNoz trace. That second group of blueprints is deliberate — a
catalog with no goals, no recorded decisions and no risks tells you *what* ran but never
*why*.

**Bright Data is both the failure and the repair.** The supplier feed it scrapes is what
breaks, and `scraper heal` is what fixes it.

The test we kept applying: pull any one out and the loop stops. Without SigNoz nothing
notices. Without Port nobody decides. Without Bright Data nothing gets fixed.

---

## How it's actually built

This section is the part worth stealing. Everything below is real code from the repo,
trimmed for readability.

### The shape

```
┌─ factory/ ──────────────────────────────────────────────────────┐
│  run.js         the pipeline: brief|incident → … → audit        │
│  telemetry.js   OTel bootstrap: traces + metrics + logs         │
│  port.js        Port REST client (machine credentials)          │
│  mise.js        the domain: shortage → routing decision         │
│  supplier.js    the live data contract, via the Bright Data CLI │
│  heal.js        detect → human gate → repair → re-verify        │
└─────────────────────────────────────────────────────────────────┘
┌─ app/ ──────────────────────────────────────────────────────────┐
│  server.js      2 data endpoints + 1 background job + SSE       │
│  public/        the console: 4 panels, one per demo beat        │
└─────────────────────────────────────────────────────────────────┘
```

No framework. Node's `http`, the OTel SDK, and `fetch`. The whole factory is about 700
lines, which matters: a factory you can't read is a factory you can't trust.

### 1. Every stage is a span, and failure has to survive

The single most reused piece of code is the stage wrapper. It opens a span, times the
stage, records failure, and closes — so no stage can forget to be observable.

```js
async function stage(name, fn) {
  const t0 = Date.now();
  return tracer.startActiveSpan(`stage.${name}`, async (span) => {
    try {
      const out = await fn(span);
      // Do NOT blanket-OK: a stage can fail its contract without throwing.
      if (!span.__failed) span.setStatus({ code: SpanStatusCode.OK });
      return out;
    } catch (e) {
      span.recordException(e);
      span.setStatus({ code: SpanStatusCode.ERROR, message: e.message });
      throw e;
    } finally {
      stageDuration.record(Date.now() - t0, { 'factory.stage': name });
      span.end();
    }
  });
}
```

That `if (!span.__failed)` guard exists because of a real bug. The original set status to
OK unconditionally after the stage body — which silently overwrote the ERROR that
`verify` sets when the data contract breaches. Stage failures were invisible to SigNoz
filters, and everything *looked* healthy.

**Lesson:** a stage that fails without throwing is normal — validation, contracts, health
checks. Make sure your instrumentation can represent "completed, but failed."

### 2. The data contract

This is the heart of it, and it's smaller than people expect:

```js
function nullRate(rows) {
  const items  = components(rows);
  const errors = collectorErrors(rows);          // surface the vendor's own error
  if (!items.length) return { rate: 1, total: 0, failingFields: REQUIRED, errors };

  const missing = {};
  for (const f of REQUIRED) missing[f] = items.filter(i => i[f] == null).length;
  const worst = Math.max(...Object.values(missing));
  return { rate: worst / items.length, total: items.length, missing, errors,
           failingFields: REQUIRED.filter(f => missing[f] > 0) };
}
```

Three decisions in there earn their keep:

- **A threshold, not zero.** Real feeds have genuine gaps. 5% separates noise from
  "extraction stopped working."
- **Track *which* fields failed**, not just the rate. That list is what makes the repair
  prompt specific enough to work.
- **Surface the collector's own errors.** Our first version returned `rate: 1, total: 0`
  and dropped the error object on the floor — throwing away the best diagnostic we had.

### 3. Wiring the contract into the pipeline

```js
const verification = await stage('verify', async (span) => {
  const n = supplier.nullRate(await supplier.scrape());
  const pass = n.rate <= NULL_THRESHOLD;

  span.setAttributes({ 'supplier.price_null_rate': n.rate, 'verify.pass': pass });
  if (!pass) {
    span.addEvent('data_contract.breached', { fields: n.failingFields.join(',') });
    span.setStatus({ code: SpanStatusCode.ERROR, message: `null-rate ${n.rate}` });
    span.__failed = true;
  }
  await port.upsert('verification', verifyId, `null-rate ${(n.rate*100).toFixed(1)}%`, {
    status: pass ? 'pass' : 'fail', null_rate: +n.rate.toFixed(4), trace_id: traceId,
  }, { verifies: buildId, checked_source: ['supplier-feed'] });
  return { rate: n.rate, pass, failingFields: n.failingFields };
});
```

One stage, three outputs: a **span** for the trace, a **metric** for the alert surface,
and an **entity** for the graph. Every stage follows that shape.

### 4. The repair prompt is the product

`scraper heal` is only as good as what you tell it. This is where "never heal blind"
becomes code:

```js
const msg =
  (n.errors.length
    ? `The collector is failing with: "${n.errors[0]}". `
    : `Extraction is returning null for [${fields}] on ${n.total} rows. `) +
  `The supplier page changed: each price used to be text like "$109.00" directly inside ` +
  `<div class="price">, and is now an empty <span data-amount="109.00"></span> nested ` +
  `inside that same div, so the text content is empty and the numeric parse fails. Read ` +
  `the price from the data-amount attribute. The product name in div.name and the SKU in ` +
  `div.meta are unchanged. Required fields: ${fields}.`;
```

Four things every repair prompt should carry: **the vendor's own error**, **what changed**,
**where the value lives now**, and **what is still fine**. Our first attempt said
`"null for [name,price] on 0 of the listed components"` — incoherent, no anchor, and it
spun for ten minutes.

### 5. Making the break reproducible

```bash
./scripts/break-mirror.sh     # rewrites price markup, commits, pushes
```

The supplier page is served from our own GitHub Pages, so a script can genuinely change
its HTML and republish. This is the difference between a demo that works and a demo that
depends on a third party redesigning their site at the right moment.

**One trap worth knowing:** after a heal, the collector reads the *new* markup — so the
two page states swap meaning. The button that repaired it yesterday breaks it today. Our
UI solved this by labelling both directions "supplier ships a redesign" and making the
computed contract status the source of truth, never the button.

### 6. Streaming a CLI into a browser

The console drives everything without a terminal. Each action spawns a process and pipes
it to the page over Server-Sent Events:

```js
function streamCommand(res, cmd, args) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
  const child = spawn(cmd, args, { cwd: ROOT, env: process.env });
  const push  = (kind, line) => res.write(`data: ${JSON.stringify({ kind, line })}\n\n`);
  let buf = '';
  child.stdout.on('data', chunk => {
    buf += chunk;
    const lines = buf.split('\n'); buf = lines.pop();
    lines.filter(l => l.trim()).forEach(l => push('out', l));
  });
  child.on('close', code => { push('done', `exit ${code}`); res.end(); });
  res.on('close', () => child.kill());          // browser closed → kill the child
}
```

That last line matters. Without it, a user closing the tab leaves a `scraper heal`
running for ten minutes with nobody listening.

### 7. Two gotchas that will bite you

**Sync APIs block the event loop.** `supplier.scrape()` uses `execFileSync`, which is
fine in a CLI and catastrophic in a server — the startup worker froze the whole process
for a minute and the console looked dead. Anything serving HTTP needs the async twin.

**Cache tokens with their expiry, not forever.** Port access tokens last about three
hours. Caching one for the life of the process meant a long-running app started failing
every write with `token has invalid claims: token is expired`. Refresh early, and retry
once on a 401:

```js
let r = await send(await token());
if (r.status === 401) r = await send(await token(true));   // forced refresh
```

### 8. Make it re-runnable, then prove it

Everything is idempotent by construction: `apply-blueprints.sh` rebuilds the whole Port
workspace in seconds, `verify.sh` runs 16 preflight checks, and the console works with no
credentials at all by replaying recorded runs.

The check that mattered most was the falsifiable one. The dispatch simulation claims to
be generated from the current run — so we wrote the test into the docs: *change the
branch numbers, re-run, and the drawing must change.* It did:

```
original  → marina 10kg (exp 2d)                        buy 26kg = $53.30
altered   → mission 11kg (exp 1d) + marina 3kg (exp 5d)  buy 22kg = $45.10
```

Two donors, nearest-expiry first, different totals. **Write down the experiment that
would prove your claim false, then run it.** If you can't think of one, the claim
probably isn't doing any work.

---

## The line in the docs that shaped the whole project

Buried in Bright Data's documentation is a sentence that reads like a limitation and is
actually the most important design decision in the product:

> Bright Data never decides a scraper is broken. **You are the detector.**

That's what forced this to be a control system rather than three API calls. If the
vendor won't tell you the scraper died, you have to define what "died" means:

- **The check** — `verify` computes a null-rate over the required fields
- **The signal** — it's published as `supplier.price_null_rate`
- **The threshold** — 5%, because real feeds have occasional genuine gaps and you need
  to separate noise from "extraction stopped working"
- **The consequence** — breach sets the span to ERROR, opens an `Incident` in Port, and
  blocks the release

Only after all of that does Bright Data get involved, and only to do the part it's
uniquely good at.

---

## Breaking it on purpose

A self-healing demo that waits for a real site to redesign itself is a demo that doesn't
happen. So the supplier page is served from our own GitHub Pages, and a script rewrites
its price markup — prices stop being text inside `.price` and become an attribute on a
renamed element — then commits and pushes. Pages republishes. The HTML genuinely changed,
via a real commit.

The collector's response was better than we hoped:

```json
{"error": "Parse error: value must be finite number", "error_code": "parse_error"}
```

It fails *loudly*. Its generated code tries to coerce a price to a number, gets an empty
string, and throws.

And we very nearly threw that away. Our first parser saw a result array with no rows and
reported "100% null over 0 rows" — technically true, and it discarded the single most
useful diagnostic available. That error message is now the first thing the repair prompt
says, because there's a rule we kept coming back to: **never heal blind.**

The prompt leads with the collector's own error, then states exactly what changed on the
page, where the value lives now, and which fields are unchanged. Result:

```
null-rate 100.0% -> 0.0%  RECOVERED
```

Re-verify passes. The release goes through. A `heal_event` lands in Port with the failing
fields and the metric value that triggered it.

---

## Four ways we got it wrong

The interesting parts of a build are rarely the parts that worked.

### The heal that "failed" for forty minutes

`brightdata scraper heal` ran for 600 seconds and the CLI gave up, suggesting we retry
with a sharper prompt. So we did — twice. We rewrote the description, softened the break,
changed the test scenario.

The retry came back `409 Another refactor job is still in progress`.

**The timeout was client-side only.** The server had kept working the entire time. The
CLI's advice actively pointed in the wrong direction: the correct action was to *wait*.
Once the lock cleared, the same call succeeded in thirty polls.

Lesson, and it generalises well beyond this tool: when an async operation reports
failure, establish whether the *work* failed or only the *waiting* did.

### Two orgs, one silent write

Halfway through, a screenshot showed `app.port.io` and a different org id than the one
from an hour earlier. There were two Port organisations on the account, in two regions.

The failure mode here is nasty: credentials from the wrong org authenticate perfectly
and write silently to the wrong place. Both API hosts answer identically to
unauthenticated probes — the only reliable way to tell which region an org lives in is
to attempt a token exchange and see which one accepts.

The apply script now tries both and reports which one authenticated.

### Overwriting a system blueprint

Our service blueprint was called `service`. So is Port's built-in one. The apply script
saw a 409, PUT over it, and stripped the schema — leaving four GitHub-fed scorecards
with rules that could no longer evaluate.

The write succeeded. Nothing warned us. We found it by reading the response line
`~ service updated (200)` and thinking *hang on, that one should have been created.*

Ours is now `factory_service`, and the script tracks what it created: a 409 on something
it didn't create is skipped with a warning rather than silently reshaped.

### Five dashboard imports

The SigNoz dashboard took five attempts, and the panel showed the same message every
time: *"Error loading JSON file."*

The actual causes, in order:

1. Legacy `widgets` schema — v0.138 wants `schemaVersion: v6`
2. Missing `image` field — validated *before* the schema, rejecting the file outright
3. `aggregations: [{expression: ...}]` — that's the traces form; metrics need
   `metricName` / `temporality` / `timeAggregation` / `spaceAggregation`
4. Capitalised `temporality` — the API enum is lowercase, unlike both ClickHouse's
   storage and the frontend's own TypeScript enum
5. `reduceTo: "avg"` — the accepted values are `last` and `sum`

Every one of those produced identical UI text. The server logs named the exact field
each time. We should have read them after the first failure instead of the fourth, and
we should have structurally diffed against a known-good published dashboard — which took
two minutes and found the last two problems immediately.

---

## What we'd tell someone starting this tomorrow

If you take nothing else from this post, take these five.

**Read the server logs before forming a theory.** Four of the five dashboard failures
were diagnosable in seconds from the response body. The UI said nothing useful, five
times, and we kept guessing anyway.

**A vendor that refuses to decide something for you is drawing a boundary, not leaving a
gap.** "You are the detector" is the reason this became a loop.

**Silent success is the enemy.** The worst bugs here all *succeeded*: the null prices,
the overwritten blueprint, the wrong-region write, the span status that got overwritten
with OK after `verify` had set it to ERROR. Every one of them returned 200.

**Instrument the thing that watches the thing.** Our contract gauges were emitted only by
the orchestrator, so the moment nobody ran the factory the dashboard went flat. The
background worker had been computing that number every two minutes and throwing it away.

**Write down the experiment that would prove your claim false.** We claimed the dispatch
simulation was generated from the live run, so we wrote the falsification into the docs:
change the branch numbers, re-run, the picture must change. It did — a different donor, a
different quantity, a different total. A claim with no test attached is marketing.

---

## Try it

The whole console runs with no accounts at all:

```bash
git clone https://github.com/abhijitbetigeri/agent-factory
cd agent-factory && npm install && npm start
```

Then `localhost:3000/console`. Without credentials it starts in demo mode and says so,
replaying transcripts recorded against the live system — including the failing run and
the repair.

With a Port org, a Bright Data key and a SigNoz endpoint in `.env`, the same console
drives the real thing: break the supplier page, watch the contract catch it, approve the
repair, and see the release unblock — all in one trace.

The app was the test run. The factory is the point.
