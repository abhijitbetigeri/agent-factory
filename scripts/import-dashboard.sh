#!/usr/bin/env bash
# Validate the factory dashboard and get it into SigNoz.
#
# Self-hosted SigNoz v0.138.0 exposes no unauthenticated dashboard API, and the JWT
# login route this script would need is not reachable (POST /api/v1/login is served by
# the static handler, not the API router, and never reaches the server's route table).
# So the reliable path is the UI importer. This script validates the JSON, checks SigNoz
# is up, and prints the exact steps rather than pretending to automate something it cannot.
set -euo pipefail
cd "$(dirname "$0")/.."
SIGNOZ="${SIGNOZ_URL:-http://localhost:8080}"
DASH=signoz/dashboard-factory-health.json

python3 - "$DASH" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
names = set()
for w in d["widgets"]:
    for q in w["query"]["builder"]["queryData"]:
        names.add(q["aggregateAttribute"]["key"])
print(f"  OK {sys.argv[1]} is valid JSON - {len(d['widgets'])} panels")
print(f"  metrics referenced: {', '.join(sorted(names))}")
PY

ver=$(curl -s --max-time 6 "$SIGNOZ/api/v1/version" || true)
if [[ "$ver" == *version* ]]; then echo "  ✅ SigNoz reachable — $ver"
else echo "  ❌ SigNoz not reachable at $SIGNOZ"; exit 1; fi

cat <<NOTE

Import it (about 20 seconds):

  1. open  $SIGNOZ/dashboard
  2. New dashboard  ->  Import JSON
  3. paste the contents of $DASH

If a panel is empty, nothing is exporting that metric yet. Run the factory once and
start the app, then reload:

  set -a && . ./.env && set +a
  node factory/run.js --brief "Route the Downtown tomato shortage"
  node app/server.js
NOTE
