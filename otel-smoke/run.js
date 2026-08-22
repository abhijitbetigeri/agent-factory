// Simulates one factory run so the trace/metric shape can be validated before the
// real orchestrator exists. Stage names here are the contract the real factory must keep.
const { sdk } = require('./tracing');
const { trace, metrics, SpanStatusCode, context } = require('@opentelemetry/api');

const tracer = trace.getTracer('factory');
const meter = metrics.getMeter('factory');

const runDuration = meter.createHistogram('factory.run.duration', { unit: 'ms' });
const stageFailure = meter.createCounter('factory.stage.failure');
const nullRate = meter.createObservableGauge('scraper.field_null_rate');

let currentNullRate = 0.0;
nullRate.addCallback((r) => r.observe(currentNullRate, { field: 'price', collector: process.env.SCRAPER_STUDIO_COLLECTOR_ID || 'c_stub' }));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const BREAK = process.env.FORCE_BREAK === '1';

async function stage(name, attrs, fn) {
  return tracer.startActiveSpan(`stage.${name}`, { attributes: attrs }, async (span) => {
    try {
      const out = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return out;
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      stageFailure.add(1, { stage: name });
      throw err;
    } finally {
      span.end();
    }
  });
}

async function main() {
  const started = Date.now();
  const runId = `run_${Math.random().toString(36).slice(2, 10)}`;

  await tracer.startActiveSpan('factory.run', {
    attributes: { 'run.id': runId, 'brief.id': 'brief_demo_001', 'agent.model': 'claude-opus-5' },
  }, async (root) => {
    const traceId = root.spanContext().traceId;
    console.error(`[factory] run=${runId} trace_id=${traceId}`);

    await stage('plan', { 'plan.steps': 4, 'approval.required': true }, () => sleep(120));
    await stage('approve', { 'approval.human': true, 'approval.actor': 'operator@demo', 'approval.gate': 'plan' }, () => sleep(40));
    await stage('build', { 'build.agent': 'claude-code', 'build.files_changed': 7 }, () => sleep(200));

    try {
      await stage('verify', { 'verify.required_fields': 'title,price', 'verify.threshold': 0.05 }, async (span) => {
        currentNullRate = BREAK ? 0.62 : 0.01;
        span.setAttribute('scraper.field_null_rate', currentNullRate);
        await sleep(90);
        if (currentNullRate > 0.05) {
          span.addEvent('scraper.heal.requested', {
            'collector.id': process.env.SCRAPER_STUDIO_COLLECTOR_ID || 'c_stub',
            reason: 'price returns null on 62% of rows after site redesign',
          });
          throw new Error(`data contract violated: null_rate=${currentNullRate}`);
        }
      });
      await stage('release', { 'release.version': '0.1.0', 'release.strategy': 'rolling' }, () => sleep(60));
      root.setStatus({ code: SpanStatusCode.OK });
    } catch (err) {
      // Failure path is a first-class outcome, not a crash: the factory escalates.
      root.addEvent('factory.escalated', { to: 'port.approval', reason: err.message });
      root.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      console.error(`[factory] ESCALATED: ${err.message}`);
    }

    runDuration.record(Date.now() - started, { outcome: BREAK ? 'escalated' : 'released' });
    root.end();
  });

  await sleep(200);
  await sdk.shutdown();
  console.error('[factory] done');
}

main();
