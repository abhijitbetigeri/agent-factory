#!/usr/bin/env bash
# Bright Data setup. Interactive: opens a browser for login.
# Idempotent — safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
BD="npx --yes --package @brightdata/cli brightdata"

echo "==> CLI version"; $BD --version

if [[ -n "${BRIGHTDATA_API_KEY:-}" ]]; then
  echo "==> Using BRIGHTDATA_API_KEY from env (headless)"
else
  echo "==> Browser login"; $BD login
fi

echo "==> Balance"; $BD budget || true

# Persist the key into .env (gitignored) so verify.sh and the MCP server can read it.
# `login` only writes ~/Library/Application Support/brightdata-cli/credentials.json.
echo "==> Syncing key into .env"
python3 - <<'PY'
import json, os, re, glob
key = os.environ.get("BRIGHTDATA_API_KEY") or ""
if not key:
    for p in glob.glob(os.path.expanduser("~/Library/Application Support/brightdata-cli/*.json")) \
           + glob.glob(os.path.expanduser("~/.config/brightdata-cli/*.json")):
        try: d = json.load(open(p))
        except Exception: continue
        if isinstance(d, dict) and d.get("api_key"):
            key = d["api_key"]; break
if not key:
    raise SystemExit("!! no API key found — run `brightdata login` first")
env = open(".env").read() if os.path.exists(".env") else ""
env, n = re.subn(r'(?m)^BRIGHTDATA_API_KEY=.*$', 'BRIGHTDATA_API_KEY=' + key, env)
if n == 0:
    env = env.rstrip("\n") + "\nBRIGHTDATA_API_KEY=" + key + "\n"
open(".env", "w").write(env)
print("   .env updated (key not printed)")
PY

echo "==> Installing agent skills"
$BD skill add brightdata-cli
$BD skill add scraper-builder

# NOTE: do NOT run `brightdata add mcp --project`. It writes the literal API token
# into .claude/settings.json, which is COMMITTED — that leaks the key (see CLAUDE.md
# "Secrets"). The bright-data server is already declared in .mcp.json using
# ${BRIGHTDATA_API_KEY} expansion, which keeps the secret in .env only.
echo "==> MCP: declared in .mcp.json via \${BRIGHTDATA_API_KEY} (nothing to do)"
python3 - <<'PY'
import json
m = json.load(open(".mcp.json"))
bd = m.get("mcpServers", {}).get("bright-data")
assert bd, "!! bright-data missing from .mcp.json"
tok = bd.get("env", {}).get("API_TOKEN", "")
assert tok.startswith("${"), f"!! .mcp.json holds a literal token — replace with ${{BRIGHTDATA_API_KEY}}"
print("   ok: .mcp.json uses env expansion, no secret committed")
PY

cat <<'NOTE'

⚠️  Claude Code must see BRIGHTDATA_API_KEY in its environment for .mcp.json
    expansion to resolve. Launch it as:

      set -a && . ./.env && set +a && claude

Next (do this the NIGHT BEFORE — scraper create takes 5-25 minutes):

  brightdata scraper create <TARGET_URL> "<fields you want, in plain English>"

Then paste the returned c_* collector ID into CLAUDE.md and .env as
SCRAPER_REAL_COLLECTOR_ID / SCRAPER_REAL_TARGET_URL, and smoke it:

  brightdata scraper run <c_id> <TARGET_URL> --pretty
NOTE
