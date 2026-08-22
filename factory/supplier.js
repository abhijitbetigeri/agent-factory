// The LIVE data contract. This is the feed routing actually depends on, and the one
// that breaks, alerts, heals, and recovers. Distinct from menu.price_null_rate, which
// is static evidence of the legacy defect — see docs/CONTRACTS.md C3.
const { execFileSync } = require('child_process');
const fs = require('fs'), path = require('path');

const FEED = path.join(__dirname, '..', 'data', 'supplier-feed.json');
const REQUIRED = (process.env.SCRAPER_REQUIRED_FIELDS || 'name,price').split(',');

/** Scrape the supplier feed through Bright Data. Terminal-only, no web UI. */
function scrape({ timeoutMs = 90000 } = {}) {
  const id = process.env.SCRAPER_MIRROR_COLLECTOR_ID;
  const url = process.env.SCRAPER_MIRROR_TARGET_URL;
  if (!id || !url) throw new Error('SCRAPER_MIRROR_COLLECTOR_ID / _TARGET_URL not set');
  const out = execFileSync('npx', ['--yes', '--package', '@brightdata/cli', 'brightdata',
    'scraper', 'run', id, url, '--sync', '--sync-timeout', '50', '--pretty'],
    { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 1 << 24 });
  const json = out.slice(out.indexOf('['));
  const rows = JSON.parse(json);
  fs.writeFileSync(FEED, JSON.stringify(rows, null, 2));
  return rows;
}

/** Normalise one scraped row to {name, price}. Shape varies after a heal, so be lenient. */
function normalise(c) {
  const name = c.product_name ?? c.name ?? c.title ?? null;
  let price = c.price_usd ?? c.price ?? null;
  if (price && typeof price === 'object') price = price.value ?? null;
  if (typeof price === 'string') {
    const m = price.match(/[\d.]+/);
    price = m ? parseFloat(m[0]) : null;
  }
  return { name: name || null, price: (price === '' ? null : price) ?? null };
}

function components(rows) {
  const out = [];
  for (const r of rows || []) for (const c of (r.components || r.items || [])) out.push(normalise(c));
  return out;
}

/**
 * The collector can fail loudly rather than returning nulls: when its generated code
 * cannot coerce a field it emits {error, error_code} instead of rows. That message is
 * the sharpest anchor we can hand to `heal`, so surface it rather than swallowing it.
 */
function collectorErrors(rows) {
  return (rows || []).filter(r => r && r.error).map(r => `${r.error_code || 'error'}: ${r.error}`);
}

/**
 * Null-rate over the required fields. This is the number the SigNoz alert watches and
 * the number `heal` has to bring back down.
 */
function nullRate(rows) {
  const items = components(rows);
  const errors = collectorErrors(rows);
  if (!items.length) return { rate: 1, total: 0, missing: {}, failingFields: REQUIRED.slice(), errors };
  const missing = {};
  for (const f of REQUIRED) missing[f] = items.filter(i => i[f] === null || i[f] === undefined).length;
  const worst = Math.max(...Object.values(missing));
  const failingFields = REQUIRED.filter(f => missing[f] / items.length > 0);
  return { rate: worst / items.length, total: items.length, missing, failingFields, errors };
}

function load() {
  try { return JSON.parse(fs.readFileSync(FEED, 'utf8')); } catch { return null; }
}

module.exports = { scrape, nullRate, components, collectorErrors, load, FEED, REQUIRED };
