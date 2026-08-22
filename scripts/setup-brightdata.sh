#!/usr/bin/env bash
# Bright Data setup. Interactive: opens a browser for login.
set -euo pipefail
BD="npx --yes --package @brightdata/cli brightdata"

echo "==> CLI version"; $BD --version

if [[ -n "${BRIGHTDATA_API_KEY:-}" ]]; then
  echo "==> Using BRIGHTDATA_API_KEY from env (headless)"
else
  echo "==> Browser login"; $BD login
fi

echo "==> Balance"; $BD budget || true

echo "==> Installing agent skills"
$BD skill add brightdata-cli
$BD skill add scraper-builder

echo "==> Adding Bright Data MCP to this project"
$BD add mcp --agent claude-code --project

cat <<'NOTE'

Next (do this the NIGHT BEFORE — scraper create takes 5-25 minutes):

  brightdata scraper create <TARGET_URL> "<fields you want, in plain English>"

Then paste the returned c_* collector ID into CLAUDE.md and .env, and smoke it:

  brightdata scraper run <c_id> <TARGET_URL> --pretty
NOTE
