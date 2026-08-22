// OTel bootstrap. Sends to SigNoz when SIGNOZ_INGESTION_KEY is set, otherwise
// prints to the console so the span/metric shape is verifiable with no account.
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { ConsoleSpanExporter, SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { PeriodicExportingMetricReader, ConsoleMetricExporter } = require('@opentelemetry/sdk-metrics');
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
});

sdk.start();
console.error(`[otel] exporting to ${remote ? ENDPOINT : 'console (no SIGNOZ_INGESTION_KEY set)'} as service=${SERVICE}`);

process.on('SIGTERM', () => sdk.shutdown().finally(() => process.exit(0)));
module.exports = { sdk, remote };
