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
import re,sys
s=open('mirror/index.html').read()
# The price stops being text inside .price and moves into an attribute on a renamed
# element. Selectors that worked yesterday now find an empty node.
s2=re.sub(r'<div class=\"price\">\\\$([\d.]+)</div>', r'<div class=\"amt\" data-cost=\"\1\"></div>', s)
open('mirror/index.html','w').write(s2)
print('  rewrote', s.count('class=\"price\"'), 'price nodes -> .amt[data-cost]')
"
  MSG="Supplier site redesign: price markup restructured"
  echo "==> price markup restructured"
fi

git add "$M"
git commit -q -m "$MSG" || { echo "(no change to commit)"; exit 0; }
git push -q origin main
echo "==> pushed. GitHub Pages republishing (~60s)."
