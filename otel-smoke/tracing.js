// OTel bootstrap. Sends to SigNoz when SIGNOZ_INGESTION_KEY is set, otherwise
// prints to the console so the span/metric shape is verifiable with no account.
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { ConsoleSpanExporter, SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { PeriodicExportingMetricReader, ConsoleMetricExporter } = require('@opentelemetry/sdk-metrics');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { SimpleLogRecordProcessor, ConsoleLogRecordExporter } = require('@opentelemetry/sdk-logs');
const { resourceFromAttributes } = require('@opentelemetry/resources');

const KEY = process.env.SIGNOZ_INGESTION_KEY;
const REGION = process.env.SIGNOZ_REGION || 'us';
const ENDPOINT = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || `https://ingest.${REGION}.signoz.cloud:443`;
const SERVICE = process.env.OTEL_SERVICE_NAME || 'factory-orchestrator';

const remote = Boolean(KEY);
const headers = remote ? { 'signoz-ingestion-key': KEY } : {};

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ 'service.name': SERVICE, 'deployment.environment': process.env.NODE_ENV || 'dev' }),
  spanProcessors: [
    new SimpleSpanProcessor(
      remote ? new OTLPTraceExporter({ url: `${ENDPOINT}/v1/traces`, headers }) : new ConsoleSpanExporter()
    ),
  ],
  metricReader: new PeriodicExportingMetricReader({
    exporter: remote ? new OTLPMetricExporter({ url: `${ENDPOINT}/v1/metrics`, headers }) : new ConsoleMetricExporter(),
    exportIntervalMillis: 5000,
  }),
  // Third signal. The SigNoz track criterion names traces, metrics, AND logs --
  // spans alone do not satisfy it. Records emitted here carry trace_id/span_id
  // automatically when written inside an active span, so a log line in SigNoz
  // links straight back to the stage that produced it.
  logRecordProcessors: [
    new SimpleLogRecordProcessor(
      remote ? new OTLPLogExporter({ url: `${ENDPOINT}/v1/logs`, headers }) : new ConsoleLogRecordExporter()
    ),
  ],
});

sdk.start();
console.error(`[otel] traces+metrics+logs -> ${remote ? ENDPOINT : 'console (no SIGNOZ_INGESTION_KEY set)'} as service=${SERVICE}`);

// The factory's logging front door. Never use console.log for factory events:
// these records are trace-correlated, the console is not.
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');
const logger = logs.getLogger(SERVICE);

const SEV = {
  debug: SeverityNumber.DEBUG, info: SeverityNumber.INFO,
  warn: SeverityNumber.WARN, error: SeverityNumber.ERROR,
};

/** Emit a trace-correlated OTel log record. `attrs` become searchable fields in SigNoz. */
function log(level, body, attrs = {}) {
  logger.emit({
    severityNumber: SEV[level] ?? SeverityNumber.INFO,
    severityText: level.toUpperCase(),
    body,
    attributes: attrs,
  });
}

process.on('SIGTERM', () => sdk.shutdown().finally(() => process.exit(0)));
module.exports = { sdk, remote, log };
