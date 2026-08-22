// Port REST client. The factory writes entities unattended, so this uses machine
// credentials rather than the MCP/OAuth path a human uses interactively.
const REGION = process.env.REGION || 'us';
const API = REGION === 'eu' ? 'https://api.port.io/v1' : 'https://api.us.port.io/v1';

let _token = null;
async function token() {
  if (_token) return _token;
  const r = await fetch(`${API}/auth/access_token`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ clientId: process.env.PORT_CLIENT_ID, clientSecret: process.env.PORT_CLIENT_SECRET }),
  });
  if (!r.ok) throw new Error(`Port auth failed: ${r.status} ${await r.text()}`);
  _token = (await r.json()).accessToken;
  return _token;
}

/** Create-or-update one entity. Every entity carries trace_id so Port links to SigNoz. */
async function upsert(blueprint, identifier, title, properties = {}, relations = {}) {
  const t = await token();
  const r = await fetch(
    `${API}/blueprints/${blueprint}/entities?upsert=true&merge=true&create_missing_related_entities=true`,
    { method: 'POST', headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ identifier, title, properties, relations }) });
  if (!r.ok) throw new Error(`Port upsert ${blueprint}/${identifier} failed: ${r.status} ${await r.text()}`);
  return (await r.json()).entity;
}

module.exports = { upsert, API };
