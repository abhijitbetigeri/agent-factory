#!/usr/bin/env bash
# Connect Claude Code to Port over MCP. Requires an interactive session for OAuth.
set -euo pipefail
REGION="${REGION:-us}"

if [[ "$REGION" == "eu" ]]; then URL="https://mcp.port.io/v1"; else URL="https://mcp.us.port.io/v1"; fi
echo "==> Adding Port MCP ($REGION): $URL"

claude mcp add --transport http port "$URL"

cat <<NOTE

Now start Claude Code interactively and complete the browser OAuth:

  claude
  > /mcp                       # confirm 'port' is connected
  > list all blueprints in my Port org

For read-only mode instead, re-add with the explicit header form:
  claude mcp add-json port '{"type":"stdio","command":"npx","args":["-y","mcp-remote","$URL","--header","x-read-only-mode: 1"]}'
NOTE
