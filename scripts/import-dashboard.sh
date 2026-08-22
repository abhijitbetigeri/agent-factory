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

python3 - "$DASH" <<'PYV'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("schemaVersion") == "v6", f"expected schemaVersion v6, got {d.get('schemaVersion')!r}"
img = d.get("image", "")
assert img.startswith("/assets/Icons") or img.startswith("/assets/Logos") or img.startswith("data:"), \
    f"image must be an /assets/Icons or /assets/Logos path, or base64 — got {img!r}. " \
    "SigNoz validates this BEFORE the schema and rejects the file with a generic " \
    "'Error loading JSON file' if it is missing."
panels = d["spec"]["panels"]
items = d["spec"]["layouts"][0]["spec"]["items"]
refs = {i["content"]["$ref"].split("/")[-1] for i in items}
assert refs == set(panels), "layout items and panels disagree"
aggs = [a for p in panels.values()
          for qq in p["spec"]["queries"]
          for bq in qq["spec"]["plugin"]["spec"]["queries"]
          for a in bq["spec"]["aggregations"]]
# Metric queries take metricName/temporality/timeAggregation/spaceAggregation.
# An "expression" here is the traces/logs form and the API rejects the whole dashboard
# with: unknown field "expression" in query spec for MetricAggregation.
for a in aggs:
    assert "expression" not in a, 'metric aggregations must not use "expression"'
    missing = {"metricName","temporality","timeAggregation","spaceAggregation"} - set(a)
    assert not missing, f"aggregation missing {missing}"
exprs = sorted({f'{a["timeAggregation"]}({a["metricName"]}) [{a["temporality"]}]' for a in aggs})
print(f"  OK {sys.argv[1]} — schemaVersion v6, {len(panels)} panels, layout consistent")
for e in exprs:
    print(f"     {e}")
PYV

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
