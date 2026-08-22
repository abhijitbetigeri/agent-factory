# Provenance

Vendored from https://github.com/leonxlnx/taste-skill (MIT), skills/taste-skill/SKILL.md.
Copied rather than installed via `npx skills add` so the content is reviewable in-tree
and pinned; re-pull deliberately, do not auto-update.

## Project overrides (these win where the skill conflicts)

The skill is explicit that its rules are contextual and that hard constraints override
aesthetic preference. For this repo:

- **Stack.** The skill defaults to React/Next + Tailwind v4 + Motion. This project ships
  static HTML with zero dependencies and no build step (`docs/BUILD-PLAN.md` slice 5,
  matching `app/public/index.html`). The stack sections do NOT apply.
- **Palette.** The skill's colour-calibration rules assume a free choice. Ours is locked
  to the tokens in `app/public/index.html` so the landing page and the approval UI read
  as one product. Do not re-pick the palette.
- **Icons.** The skill says use Phosphor/Radix rather than hand-rolled SVG. We ship no
  icon dependency; the one inline SVG is an architecture diagram that organises real
  content, which the skill permits.

Everything else applies, in particular section 9 (AI Tells) and 9.G (em-dash ban).
