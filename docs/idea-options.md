# The open decision: which use case

Status: **UNDECIDED** as of 2026-08-22. Nothing downstream is blocked except
`brightdata scraper create` (5-25 min), which needs a target URL.

## The two filters that actually matter

1. **Does it build software?** The headline question is *"can you build the factory that
   builds the app?"* An idea that only maintains a pipeline can sweep the track prizes
   and still lose the grand prize.
2. **Is Bright Data a participant or a garnish?** The grand prize says "seamlessly
   combines." Judges will notice an idea where BD is bolted on for context.

## Scoring

| Idea | Builds software? | All 3 load-bearing? | 12h risk | Crowded? |
|---|---|---|---|---|
| 1. Brief-to-App | ✅ core | ⚠️ BD is an ingredient, SigNoz only watches | Low, scope unbounded | **Very** — the default read |
| 2. Self-Healing Data | ❌ maintains a pipeline | ✅ genuine loop | Low | Medium |
| 3. Competitor-Watch | ✅ | ✅ BD is the *sensor* | Medium | **Low** |
| 4. Docs-to-RAG | ⚠️ builds a bot once | ✅ | **High** — eval eats the clock | Low |
| 5. Incident-to-Fix | ✅ | ⚠️ BD is a garnish | Medium-high | Low |

## Standing recommendation: #3, with #2's heal loop nested inside

- **BD becomes the sensor.** A diff it detects *starts* the factory, rather than feeding
  an app the factory already built. Strongest possible Bright Data story.
- **"Handles changing requirements"** — a named judging criterion most teams will fake —
  is the premise. The web changing *is* the requirement changing.
- **Two closed loops, not one.** Product loop (competitor change → software change →
  approval → release) with the repair loop (scraper breaks → null-rate alert → Port gate
  → `brightdata heal`) nested inside it.
- **Port gets something real to govern**: change requests with spec, risk, and approval —
  which is the Port track criterion nearly verbatim.

**The trap in #3:** the phrase *"builds a prototype response."* Left vague it eats the
night. Pin the build target to something tiny and concrete (one section of a comparison
page) before starting, or pick a different idea.

## Candidate watch targets (if #3)

Needs static-ish HTML, changes often, one visually obvious required field.

- **Sponsor pricing/changelogs** — the factory maintains a comparison page about the
  tools it is built from. Memorable, self-referential, public data.
- **Observability vendor pricing** — serious narrative, but JS-heavy and fragile.
- **Dev-tool changelogs** — lowest scrape risk, but a new changelog entry is a less
  striking break than a price vanishing.

## What does NOT depend on this decision

The OTel spine (traces + logs + metrics), the 12 Port blueprints, the approval gates,
the scorecard, the setup scripts, and the demo-video structure are all idea-agnostic.
Build them now; bind the target URL later.
