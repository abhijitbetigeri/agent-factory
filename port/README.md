# Port workspace

12 blueprints. **None of them depend on which use case we pick** — they model the
factory, not the app. Safe to apply as soon as Port credentials exist.

## Why 12 and not 8

The original design had 8 pipeline blueprints. The Port track prize is awarded for
"the clearest workspace setup showing **project goals, technical choices, risk factors,
and cataloged services**." Those four were entirely missing. `goal`,
`technical_decision`, `risk`, and `service` exist specifically to win that prize —
an empty workspace loses it no matter how good the pipeline graph is.

## The graph

```
        goal ◀──── risk
         ▲  ▲
         │  └──── technical_decision ────▶ service ◀──── data_source
         │                                   ▲                │
       brief ──▶ plan ──▶ build_run ──▶ verification ──▶ release
                            │               │
                  agent_invocation      heal_event ──▶ data_source
```

Relations matter more than the blueprints. The graph is what makes *"what happened and
why"* answerable in a single query — and every entity carries `trace_id`, so any node
jumps straight to its SigNoz trace.

## Apply order (relations require their target to exist first)

```
1. goal, service                 (no relations)
2. technical_decision, risk      (-> goal, service)
3. brief                         (-> goal)
4. plan                          (-> brief, technical_decision)
5. data_source                   (-> service)
6. build_run                     (-> plan, service)
7. verification                  (-> build_run, data_source)
8. heal_event                    (-> data_source, verification)
9. release                       (-> verification, service)
10. agent_invocation             (-> build_run, plan)
```

`./scripts/apply-blueprints.sh` applies them in exactly this order.

## Two ways in

- **AI Builder (preferred, and what the brief rewards):** paste `docs/factory-design.md`
  into AI Builder, use **Plan mode first**, capture the proposed plan as a submission
  artifact, review it, then Build. Faster than hand-authoring and it demonstrates the
  Plan/Build distinction judges asked about.
- **API (deterministic, repeatable):** `./scripts/apply-blueprints.sh`. Use this if AI
  Builder drifts from the schema, and for the "run it again" reproducibility story.

## Note on icons

Icon names are cosmetic. If Port rejects one as unknown, drop the `icon` key — it does
not affect the schema or relations.
