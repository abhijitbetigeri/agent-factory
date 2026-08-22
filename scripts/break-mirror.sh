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
  # Detect the price TEXT, not the .price class: the break now keeps the .price div
  # and empties it, so a class-only test would pass on an already-broken page and
  # silently no-op instead of warning.
  grep -qE '<div class="price">\$[0-9]' "$M" || { echo "!! $M already broken (no price text) — nothing to break."; \
                                    echo "   run: $0 --reset"; exit 1; }
  python3 scripts/_mirror_edit.py break
  MSG="Supplier site redesign: price markup restructured"
  echo "==> price markup restructured"
fi

git add "$M"
git commit -q -m "$MSG" || { echo "(no change to commit)"; exit 0; }
git push -q origin main
echo "==> pushed. GitHub Pages republishing (~60s)."
