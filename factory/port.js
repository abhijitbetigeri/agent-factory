// Port REST client. The factory writes entities unattended, so this uses machine
// credentials rather than the MCP/OAuth path a human uses interactively.
const REGION = process.env.REGION || 'us';
const API = REGION === 'eu' ? 'https://api.port.io/v1' : 'https://api.us.port.io/v1';

// Port access tokens expire (expires_in is ~3h). Caching one for the life of the
// process meant a long-running app started failing every write with
// "token has invalid claims: token is expired". Cache with an expiry and refresh.
let _token = null, _expiresAt = 0;
async function token(force = false) {
  if (!force && _token && Date.now() < _expiresAt) return _token;
  const r = await fetch(`${API}/auth/access_token`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ clientId: process.env.PORT_CLIENT_ID, clientSecret: process.env.PORT_CLIENT_SECRET }),
  });
  if (!r.ok) throw new Error(`Port auth failed: ${r.status} ${await r.text()}`);
  const j = await r.json();
  _token = j.accessToken;
  // Refresh a minute early rather than racing the expiry.
  _expiresAt = Date.now() + ((j.expiresIn || j.expires_in || 3600) * 1000) - 60000;
  return _token;
}

/** Create-or-update one entity. Every entity carries trace_id so Port links to SigNoz. */
async function upsert(blueprint, identifier, title, properties = {}, relations = {}) {
  const send = async (t) => fetch(
    `${API}/blueprints/${blueprint}/entities?upsert=true&merge=true&create_missing_related_entities=true`,
    { method: 'POST', headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ identifier, title, properties, relations }) });

  let r = await send(await token());
  // A token can expire between the cache check and the request, or be revoked. One
  // forced refresh and retry costs nothing and avoids failing a live demo.
  if (r.status === 401) r = await send(await token(true));
  if (!r.ok) throw new Error(`Port upsert ${blueprint}/${identifier} failed: ${r.status} ${await r.text()}`);
  return (await r.json()).entity;
}

module.exports = { upsert, API };
