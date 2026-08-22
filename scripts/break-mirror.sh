#!/usr/bin/env bash
# Break the supplier page's HTML the way a real site redesign would, commit it, and let
# GitHub Pages republish. This is the "source site changed its structure" event, made
# reproducible -- which is what the organizers' own prep advice tells you to rehearse.
#
#   ./scripts/break-mirror.sh          break it
#   ./scripts/break-mirror.sh --reset  restore the working markup
set -euo pipefail
cd "$(dirname "$0")/.."
M=mirror/index.html

# mirror/index.baseline.html is the pristine copy. Restoring from it is exact, which
# matters when rehearsing: the break must be the only break on camera.
B=mirror/index.baseline.html

if [[ "${1:-}" == "--reset" ]]; then
  # Guard: the baseline was previously only *referenced*, never created, so --reset
  # died on a missing file and the break was irreversible. Fail loudly instead.
  [[ -f "$B" ]] || { echo "!! $B missing — cannot reset. Recover with:"; \
                     echo "   git show 76d8e66:mirror/index.html > $B"; exit 1; }
  cp "$B" "$M"
  MSG="Supplier site: revert to previous markup"
  echo "==> mirror restored from baseline"
else
  # Snapshot the pristine markup BEFORE the first break, so --reset always has a
  # target. Never overwrite it — a second break must not baseline a broken page.
  if [[ ! -f "$B" ]]; then
    cp "$M" "$B"; git add "$B"
    echo "==> baseline snapshotted -> $B"
  fi
  grep -q 'class="price"' "$M" || { echo "!! $M already broken (no .price nodes) — nothing to break."; \
                                    echo "   run: $0 --reset"; exit 1; }
  python3 -c "
import re
s=open('mirror/index.html').read()
# Break ONLY the price field, and leave the row structure intact. This is what a real
# site tweak looks like: the rows still parse, the product names still extract, but the
# price is no longer text where it used to be. A collector that returns rows with one
# null field is both a truer failure mode and something heal can actually repair -- an
# earlier, more destructive break renamed the row container too, the extraction
# returned zero rows, and heal timed out at 600s with nothing to anchor on.
s2=re.sub(r'<div class=\\"price\\">\\\$([\d.]+)</div>',
          r'<div class=\\"price\\"><span data-amount=\\"\\1\\"></span></div>', s)
open('mirror/index.html','w').write(s2)
print('  emptied', s.count('class=\\"price\\"'), 'price nodes (rows + names left intact)')
"
  MSG="Supplier site redesign: price markup restructured"
  echo "==> price markup restructured"
fi

git add "$M"
git commit -q -m "$MSG" || { echo "(no change to commit)"; exit 0; }
git push -q origin main
echo "==> pushed. GitHub Pages republishing (~60s)."
