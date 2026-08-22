#!/usr/bin/env node
/**
 * The factory. brief|incident -> plan -> build -> verify -> approve -> release -> audit.
 *
 * Every stage is one OTel span under a single `factory.run` root, and one entity in
 * Port carrying that run's trace_id. If it is not traced, it did not happen.
 *
 *   node run.js --brief "add expiry-weighted routing"
 *   node run.js --incident data_source_broken
 */
const { log } = require('./telemetry');            // must load first: starts the SDK
const { trace, metrics, SpanStatusCode, context } = require('@opentelemetry/api');
const port = require('./port');
const mise = require('./mise');
const crypto = require('crypto');

const tracer = trace.getTracer('mise-os-factory');
const meter = metrics.getMeter('mise-os-factory');
const nullRateGauge = meter.createObservableGauge('menu.price_null_rate');
const stageDuration = meter.createHistogram('factory.stage.duration', { unit: 'ms' });
let LAST_NULL_RATE = 0;
nullRateGauge.addCallback(r => r.observe(LAST_NULL_RATE));

const argv = process.argv.slice(2);
const arg = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const BRIEF = arg('--brief');
const INCIDENT = arg('--incident');
const AUTO_APPROVE = argv.includes('--auto-approve');
const RUN = `run-${Date.now()}`;
const NULL_THRESHOLD = parseFloat(process.env.SCRAPER_NULL_RATE_THRESHOLD || '0.05');

/** Run one stage as a span, time it, and record failure as span status ERROR. */
async function stage(name, fn) {
  const t0 = Date.now();
  return tracer.startActiveSpan(`stage.${name}`, async (span) => {
    try {
      const out = await fn(span);
      // Do NOT blanket-OK: a stage can fail its contract without throwing (verify does
      // exactly that), and overwriting its ERROR status would hide the failure from
      // SigNoz filters. Only mark OK if the stage did not already mark itself ERROR.
      if (!span.__failed) span.setStatus({ code: SpanStatusCode.OK });
      return out;
    } catch (e) {
      span.recordException(e);
      span.setStatus({ code: SpanStatusCode.ERROR, message: e.message });
      log('error', `stage ${name} failed: ${e.message}`, { 'factory.stage': name });
      throw e;
    } finally {
      const ms = Date.now() - t0;
      stageDuration.record(ms, { 'factory.stage': name });
      span.setAttribute('factory.stage.duration_ms', ms);
      span.end();
      console.log(`  ${name.padEnd(9)} ${String(ms).padStart(5)}ms`);
    }
  });
}

async function main() {
  const rootSpan = tracer.startSpan('factory.run');
  const traceId = rootSpan.spanContext().traceId;
  const ctx = trace.setSpan(context.active(), rootSpan);

  console.log(`\n=== factory.run ${RUN} ===`);
  console.log(`trace_id ${traceId}`);
  console.log(`trigger  ${INCIDENT ? `incident:${INCIDENT}` : `brief:"${BRIEF}"`}\n`);

  await context.with(ctx, async () => {
    const origin = INCIDENT ? 'incident' : 'human';
    let incidentId = null;

    // ── entry: an alert, or a human brief. Same pipeline either way. ──────────
    if (INCIDENT) {
      incidentId = `inc-${RUN}`;
      await stage('incident', async (span) => {
        const mi = mise.loadMenuIntel();
        const rate = mise.priceNullRate(mi);
        LAST_NULL_RATE = rate;
        span.setAttributes({ 'incident.class': INCIDENT, 'menu.price_null_rate': rate });
        log('error', `incident opened: ${INCIDENT}`, { 'incident.class': INCIDENT, rate });
        await port.upsert('incident', incidentId, `Price feed degraded (${(rate * 100).toFixed(1)}% null)`, {
          incident_class: INCIDENT, severity: 'sev2', status: 'triaging',
          detected_by: 'signoz alert: menu.price_null_rate',
          signal: `menu.price_null_rate=${rate.toFixed(4)} > ${NULL_THRESHOLD}`,
          fix_path: 'scraper_heal', detected_at: new Date().toISOString(), trace_id: traceId,
        });
      });
    }

    const briefId = `brief-${RUN}`;
    const briefBody = BRIEF || `Auto-raised from ${INCIDENT}: routing is running on stale prices`;
    await stage('brief', async () => {
      await port.upsert('brief', briefId, briefBody.slice(0, 60), {
        body: briefBody, origin, source: origin === 'human' ? 'human' : 'automation',
        submitted_at: new Date().toISOString(), trace_id: traceId,
      });
    });

    // ── plan: read the Context Lake, decide, gate ────────────────────────────
    const planId = `plan-${RUN}`;
    const decision = await stage('plan', async (span) => {
      const mi = mise.loadMenuIntel();
      const d = mise.plan();
      span.setAttributes({
        'plan.tasks': d.tasks.length, 'plan.requires_approval': d.requiresHumanApproval,
        'plan.buy_cost_usd': d.buy.cost, 'menu.ingredients': mi.ingredients.size,
      });
      log('info', `plan: ${d.summary}`, { 'factory.stage': 'plan' });
      await port.upsert('plan', planId, d.summary, {
        steps: d.tasks.map(t => `[${t.executor}] ${t.kind}: ${t.rationale}`),
        risk_summary: `risk ${d.risk}; ${d.requiresHumanApproval ? 'human gate required' : 'auto'}`,
        estimated_steps: d.tasks.length,
        approval_status: 'pending', trace_id: traceId,
      }, { from_brief: briefId });
      await port.upsert('agent_invocation', `agent-plan-${RUN}`, 'planner', {
        agent: 'planner', model: 'rule-based-v1', outcome: 'success', trace_id: traceId,
      }, { produced_plan: planId });
      return d;
    });

    // ── build: produce the dispatch the OS will execute ──────────────────────
    const buildId = `build-${RUN}`;
    await stage('build', async (span) => {
      span.setAttribute('build.tasks_emitted', decision.tasks.length);
      require('fs').writeFileSync(
        require('path').join(__dirname, '..', 'data', 'dispatch.json'),
        JSON.stringify({ run: RUN, trace_id: traceId, ...decision }, null, 2));
      await port.upsert('build_run', buildId, `dispatch for ${RUN}`, {
        status: 'succeeded', attempt: 1, trace_id: traceId,
      }, { executes_plan: planId });
    });

    // ── verify: the data contract. This is the sensor everything hangs off. ──
    const verifyId = `verify-${RUN}`;
    const verification = await stage('verify', async (span) => {
      const mi = mise.loadMenuIntel();
      const rate = mise.priceNullRate(mi);
      LAST_NULL_RATE = rate;
      const pass = rate <= NULL_THRESHOLD;
      span.setAttributes({ 'menu.price_null_rate': rate, 'verify.threshold': NULL_THRESHOLD, 'verify.pass': pass });
      if (!pass) {
        span.addEvent('data_contract.breached', { field: 'price', rate });
        span.setStatus({ code: SpanStatusCode.ERROR, message: `null-rate ${rate.toFixed(4)} > ${NULL_THRESHOLD}` });
        span.__failed = true;
        log('error', `data contract breached: price null-rate ${(rate * 100).toFixed(1)}%`,
            { 'factory.stage': 'verify', 'scraper.field': 'price' });
      }
      await port.upsert('verification', verifyId, `null-rate ${(rate * 100).toFixed(1)}%`, {
        status: pass ? 'pass' : 'fail', contract_ok: pass, null_rate: +rate.toFixed(4),
        tests_passed: pass ? 1 : 0, tests_failed: pass ? 0 : 1, trace_id: traceId,
      }, { verifies: buildId });
      return { rate, pass };
    });

    // ── approve: human gate. A failing contract escalates rather than releases ─
    const approved = await stage('approve', async (span) => {
      const needsHuman = decision.requiresHumanApproval || !verification.pass;
      const ok = AUTO_APPROVE || !needsHuman;
      span.setAttributes({ 'approve.required': needsHuman, 'approve.granted': ok });
      await port.upsert('plan', planId, decision.summary, {
        approval_status: ok ? 'approved' : 'pending',
        approved_by: ok ? (AUTO_APPROVE ? 'auto-approve flag' : 'not required') : '',
      });
      log(ok ? 'info' : 'warn', ok ? 'approved' : 'AWAITING HUMAN APPROVAL', { 'factory.stage': 'approve' });
      return ok;
    });

    // ── release ──────────────────────────────────────────────────────────────
    if (approved && verification.pass) {
      await stage('release', async () => {
        await port.upsert('release', `rel-${RUN}`, `Mise OS dispatch ${RUN}`, {
          version: RUN, environment: 'dev', approved_by: 'human gate',
          released_at: new Date().toISOString(), trace_id: traceId,
        }, { gated_by: verifyId });
      });
    } else {
      console.log(`  release   SKIPPED (${!verification.pass ? 'contract failed' : 'awaiting approval'})`);
    }

    await stage('audit', async (span) => {
      span.setAttributes({ 'audit.trace_id': traceId, 'audit.run': RUN });
    });

    console.log(`\n${decision.summary}`);
    for (const t of decision.tasks) console.log(`  [${t.executor.padEnd(5)}] ${t.kind}: ${t.rationale}`);
    console.log(`\nnull-rate ${(verification.rate * 100).toFixed(1)}% (threshold ${NULL_THRESHOLD * 100}%) -> ${verification.pass ? 'PASS' : 'FAIL'}`);
    console.log(`Port: https://app.us.port.io   SigNoz: http://localhost:8080  trace ${traceId}`);
  });

  rootSpan.end();
  await new Promise(r => setTimeout(r, 6000));   // let the exporters flush
}

main().catch(e => { console.error('factory failed:', e.message); process.exit(1); });
