#!/usr/bin/env node
/**
 * Repair a broken collector through Bright Data, behind a human gate.
 *
 * Never heals blind: the concrete failing field names come from the verify check, per
 * the rule in CLAUDE.md. Bright Data does not decide a scraper is broken — we do.
 *
 *   node heal.js                 # detect, then ask for approval
 *   node heal.js --auto-approve  # unattended (factory-driven)
 */
const { log } = require('./telemetry');
const { trace, SpanStatusCode, context } = require('@opentelemetry/api');
const { execFileSync } = require('child_process');
const port = require('./port');
const supplier = require('./supplier');

const tracer = trace.getTracer('mise-os-factory');
const AUTO = process.argv.includes('--auto-approve');
const RUN = `heal-${Date.now()}`;
const THRESHOLD = parseFloat(process.env.SCRAPER_NULL_RATE_THRESHOLD || '0.05');
const ID = process.env.SCRAPER_MIRROR_COLLECTOR_ID;
const URL = process.env.SCRAPER_MIRROR_TARGET_URL;

const bd = (args, timeout = 900000) =>
  execFileSync('npx', ['--yes', '--package', '@brightdata/cli', 'brightdata', ...args],
    { encoding: 'utf8', timeout, maxBuffer: 1 << 24, stdio: ['ignore', 'pipe', 'inherit'] });

async function main() {
  const root = tracer.startSpan('factory.heal');
  const traceId = root.spanContext().traceId;
  console.log(`\n=== ${RUN} ===\ntrace_id ${traceId}\n`);

  await context.with(trace.setSpan(context.active(), root), async () => {
    // 1. Detect. Detection is ours, not the CLI's.
    let rows; try { rows = supplier.scrape(); } catch { rows = supplier.load(); }
    const n = supplier.nullRate(rows);
    console.log(`null-rate ${(n.rate * 100).toFixed(1)}% over ${n.total} rows  missing=${JSON.stringify(n.missing)}`);
    if (n.errors && n.errors.length) console.log(`collector error: ${n.errors[0]}`);
    if (n.rate <= THRESHOLD) { console.log('contract holds — nothing to heal'); root.end(); return; }

    const fields = n.failingFields.join(',');
    // Never heal blind (CLAUDE.md). Lead with the collector's OWN error when it gave us
    // one - it names the exact failure inside the generated code - then say what changed
    // on the page and where the value actually lives now.
    const msg = (n.errors && n.errors.length
        ? `The collector is failing with: "${n.errors[0]}". `
        : `Extraction is returning null for [${fields}] on ${n.total} rows. `) +
      `The supplier page changed: each price used to be text like "$109.00" directly inside ` +
      `<div class="price">, and is now an empty <span data-amount="109.00"></span> nested inside ` +
      `that same div, so the text content is empty and the numeric parse fails. Read the price ` +
      `from the data-amount attribute of the span inside div.price. The product name in ` +
      `div.name and the SKU in div.meta are unchanged. Required fields: ${fields}.`;

    root.addEvent('scraper.heal.requested', { fields, rate: n.rate });
    log('error', `heal requested for [${fields}] at ${(n.rate * 100).toFixed(1)}% null`, { 'scraper.fields': fields });

    const healId = `heal-${RUN}`;
    await port.upsert('heal_event', healId, `Repair ${fields} on supplier feed`, {
      trigger: `supplier.price_null_rate=${n.rate.toFixed(4)} > ${THRESHOLD}`,
      failing_fields: n.failingFields, outcome: 'requested', auto_approved: AUTO,
      requested_at: new Date().toISOString(), trace_id: traceId,
    }, { repairs: 'supplier-feed' });

    // 2. Human gate.
    if (!AUTO) {
      console.log(`\n--- HUMAN APPROVAL REQUIRED ---\nRepair [${fields}] on ${ID}?`);
      process.stdout.write('type "approve" to proceed: ');
      const answer = require('fs').readFileSync(0, 'utf8').trim();
      if (answer !== 'approve') {
        await port.upsert('heal_event', healId, `Repair ${fields} on supplier feed`, { outcome: 'rejected' });
        console.log('rejected — no repair attempted'); root.end(); return;
      }
    }
    root.addEvent('scraper.heal.approved', { approver: AUTO ? 'auto' : 'human' });

    // 3. Repair, then re-verify.
    console.log('\nhealing (this takes a few minutes)...');
    bd(['scraper', 'heal', ID, msg, '--url', URL, '--auto-approve', '--auto-save']);

    const after = supplier.nullRate(supplier.scrape());
    const fixed = after.rate <= THRESHOLD;
    console.log(`\nnull-rate ${(n.rate * 100).toFixed(1)}% -> ${(after.rate * 100).toFixed(1)}%  ${fixed ? 'RECOVERED' : 'STILL BROKEN'}`);
    if (!fixed) { root.setStatus({ code: SpanStatusCode.ERROR, message: 'heal did not restore the contract' }); }

    await port.upsert('heal_event', healId, `Repair ${fields} on supplier feed`, {
      outcome: fixed ? 'resolved' : 'failed',
      approver: AUTO ? 'auto-approve' : 'human',
      resolved_at: new Date().toISOString(),
    });
    await port.upsert('data_source', 'supplier-feed', 'Supplier price feed (c_mirror)', {
      health: fixed ? 'healthy' : 'broken', record_count: after.total,
      last_scraped_at: new Date().toISOString(),
    });
    log(fixed ? 'info' : 'error', `heal ${fixed ? 'resolved' : 'failed'}`, { 'scraper.fields': fields });
  });

  root.end();
  await new Promise(r => setTimeout(r, 6000));
}
main().catch(e => { console.error('heal failed:', e.message); process.exit(1); });
