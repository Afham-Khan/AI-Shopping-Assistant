/* Smoke test of the Vercel function entry (api/index.js) against the hosted database, as close to Vercel as we can
   get without the Vercel CLI: the handler is loaded the way Vercel loads it (no server.js, no app.listen of ours,
   no backend/.env), wrapped in a plain Node http server like Vercel's launcher, and called over HTTP.

   Environment, read from files that never leave this machine and are never printed:
     backend/.env.render   NODE_ENV, JWT secrets, CORS, LLM settings ... (same names as on Vercel)
     backend/.env.neon     DATABASE_URL (direct) and DATABASE_URL_POOLED (the "-pooler" host, preferred)
   forced: AI_EMBEDDINGS=tfidf, AI_VISUAL=off, IMAGE_MODE=cdn, SERVERLESS=1 (small pool, lazy AI index like on Vercel)

   Usage (from backend/):  node scripts/smokeServerless.js            two passes: cold, then warm
                           node scripts/smokeServerless.js --no-llm   force LLM_PROVIDER=none (no Gemini quota used)
                           node scripts/smokeServerless.js --direct   use the direct (non-pooled) Neon host
                           node scripts/smokeServerless.js --func <dir>   load api/vercel.mjs from a folder holding only
                                the files Vercel would bundle (proves nothing the function needs was left out)
   Writes to the database only what a demo user would: one chat conversation (deleted at the end) and one refresh
   token (revoked at the end by logout). */
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { parse } = require('dotenv');

const { pathToFileURL } = require('url');

const BACKEND = path.join(__dirname, '..');
const argv = process.argv.slice(2);
const args = new Set(argv);
const funcIndex = argv.indexOf('--func');
const FUNCTION_ROOT = funcIndex >= 0 ? path.resolve(argv[funcIndex + 1]) : BACKEND;

const readEnv = (name) => {
  const file = path.join(BACKEND, name);
  if (!fs.existsSync(file)) {
    console.error(`Missing backend/${name}.`);
    process.exit(1);
  }
  return parse(fs.readFileSync(file));
};

const render = readEnv('.env.render');
const neon = readEnv('.env.neon');
const pooled = neon.DATABASE_URL_POOLED;
const direct = neon.DATABASE_URL;
if (!pooled && !direct) {
  console.error('backend/.env.neon has neither DATABASE_URL_POOLED nor DATABASE_URL.');
  process.exit(1);
}

// a clean environment like a fresh Vercel instance: none of the API's own settings may leak in from this shell
// (operating-system variables stay, Windows needs some of them for DNS)
const APP_SETTING = /^(DB_|DATABASE_URL|TEST_DATABASE_URL|JWT_|REFRESH_TOKEN|CORS_|IMAGE_MODE|AI_|LLM_|GEMINI_|GROQ_|SMTP_|MAIL_FROM|PUBLIC_BASE_URL|PORT$|NODE_ENV$|VISUAL_|ADMIN_PASSWORD|VERCEL|SERVERLESS)/;
for (const key of Object.keys(process.env)) if (APP_SETTING.test(key)) delete process.env[key];
const { NODE_VERSION, PORT, ...deployed } = render; // host-only settings
Object.assign(process.env, deployed, {
  AI_EMBEDDINGS: 'tfidf',
  AI_VISUAL: 'off',
  IMAGE_MODE: 'cdn',
  SERVERLESS: '1',
  DATABASE_URL: args.has('--direct') ? direct : (pooled || direct),
});
if (args.has('--direct')) delete process.env.DATABASE_URL_POOLED;
else if (pooled) process.env.DATABASE_URL_POOLED = pooled;
if (args.has('--no-llm')) process.env.LLM_PROVIDER = 'none';

// Vercel runs the function from its own folder without a .env file; dotenv in app.js must not find backend/.env
process.chdir(os.tmpdir());

const hostOnly = (url) => {
  try {
    return new URL(url).hostname;
  } catch {
    return '(unparseable)';
  }
};

const ms = (t0) => Math.round(Number(process.hrtime.bigint() - t0) / 1e6);

const main = async () => {
  console.log(`database host: ${hostOnly(process.env.DATABASE_URL_POOLED || process.env.DATABASE_URL)}${args.has('--direct') ? ' (direct)' : ''}`);
  console.log(`NODE_ENV=${process.env.NODE_ENV} AI_EMBEDDINGS=tfidf AI_VISUAL=off LLM_PROVIDER=${process.env.LLM_PROVIDER || 'none'}`);

  if (FUNCTION_ROOT !== BACKEND) console.log(`function files from: ${FUNCTION_ROOT}`);
  let t0 = process.hrtime.bigint();
  const entry = await import(pathToFileURL(path.join(FUNCTION_ROOT, 'api', 'vercel.mjs')).href);
  const handler = entry.default;
  const requireMs = ms(t0);
  const loaded = Object.keys(require.cache);
  const heavy = loaded.filter((f) => /onnxruntime|@huggingface|[\\/]sharp[\\/]/.test(f));
  console.log(`module load (cold start part 1): ${requireMs} ms, ${loaded.length} modules, heavy AI modules loaded: ${heavy.length}, maxDuration=${entry.config?.maxDuration}s`);

  const server = http.createServer(handler);
  await new Promise((resolve) => { server.listen(0, '127.0.0.1', resolve); });
  const base = `http://127.0.0.1:${server.address().port}/api/v1`;

  const call = async (method, url, { body, token } = {}) => {
    const start = process.hrtime.bigint();
    const res = await fetch(base + url, {
      method,
      headers: {
        'content-type': 'application/json',
        origin: 'https://zelora.vercel.app',
        ...(token && { authorization: `Bearer ${token}` }),
      },
      body: body && JSON.stringify(body),
    });
    const json = await res.json().catch(() => null);
    return { status: res.status, ms: ms(start), json, cors: res.headers.get('access-control-allow-origin') };
  };

  const results = [];
  const cleanup = { conversations: new Set(), refreshTokens: new Set() };

  const pass = async (label) => {
    const row = (name, r, note = '') => {
      results.push({ pass: label, name, status: r.status, ms: r.ms, note });
      console.log(`${label.padEnd(5)} ${name.padEnd(34)} ${String(r.status).padEnd(4)} ${String(r.ms).padStart(6)} ms  ${note}`);
      return r;
    };
    const health = row('GET  /health', await call('GET', '/health'));
    if (label === 'cold') console.log(`      CORS for https://zelora.vercel.app: ${health.cors || 'not allowed'}`);
    const home = row('GET  /catalog/home', await call('GET', '/catalog/home'));
    const sections = home.json?.data && typeof home.json.data === 'object' ? Object.keys(home.json.data).length : 0;
    if (label === 'cold') console.log(`      home sections: ${sections}`);
    const list = await call('GET', '/products?limit=12');
    const items = list.json?.data?.items || list.json?.data || [];
    row('GET  /products?limit=12', list, `${Array.isArray(items) ? items.length : '?'} products`);
    const demo = await call('POST', '/auth/demo');
    row('POST /auth/demo', demo, demo.json?.data?.user?.email ? 'signed in as demo user' : (demo.json?.message || ''));
    const token = demo.json?.data?.accessToken;
    if (demo.json?.data?.refreshToken) cleanup.refreshTokens.add(demo.json.data.refreshToken);
    if (!token) return;

    const chats = [
      ['POST /ai/chat (English)', 'wireless earbuds under 5000'],
      ['POST /ai/chat (Roman Urdu)', 'mujhe 3000 tak ka acha perfume chahiye'],
      ['POST /ai/chat (compare first two)', 'compare the first two'],
    ];
    let conversationId = null;
    for (const [name, message] of chats) {
      const r = await call('POST', '/ai/chat', { token, body: { message, conversationId } });
      conversationId = r.json?.data?.conversationId || conversationId;
      if (conversationId) cleanup.conversations.add(conversationId);
      const meta = r.json?.data?.message?.meta || {};
      const products = (meta.products || meta.cards || []).length;
      const reply = String(r.json?.data?.message?.content || r.json?.message || '').replace(/\s+/g, ' ');
      row(name, r, `intent=${meta.intent || '?'} products=${products} "${reply.slice(0, 60)}${reply.length > 60 ? '…' : ''}"`);
    }
    const recs = await call('GET', '/ai/recommendations?limit=8', { token });
    row('GET  /ai/recommendations', recs, `${(recs.json?.data?.products || []).length} products, strategy=${recs.json?.data?.strategy || '?'}`);
    const bundle = await call('POST', '/ai/bundle', { token, body: { goal: 'home office setup', budget: 150000 } });
    const b = bundle.json?.data || {};
    row('POST /ai/bundle', bundle, bundle.status >= 400
      ? String(bundle.json?.message || '')
      : `"${b.title}": ${(b.items || []).length} items, total ${b.total} of ${b.budget}, skipped roles ${(b.skippedRoles || []).length}`);
  };

  t0 = process.hrtime.bigint();
  await pass('cold');
  console.log(`cold pass total: ${ms(t0)} ms (first database connection + lazy AI catalog index included)`);
  t0 = process.hrtime.bigint();
  await pass('warm');
  console.log(`warm pass total: ${ms(t0)} ms`);

  // leave the demo account as we found it
  const demo = await call('POST', '/auth/demo');
  const token = demo.json?.data?.accessToken;
  if (demo.json?.data?.refreshToken) cleanup.refreshTokens.add(demo.json.data.refreshToken);
  for (const id of cleanup.conversations) await call('DELETE', `/ai/conversations/${id}`, { token });
  for (const refreshToken of cleanup.refreshTokens) await call('POST', '/auth/logout', { body: { refreshToken } });
  console.log(`cleanup: deleted ${cleanup.conversations.size} conversation(s), revoked ${cleanup.refreshTokens.size} refresh token(s)`);

  const insights = await call('GET', '/ai/insights');
  const engine = insights.json?.data || {};
  console.log(`AI engine: retrieval=${engine.embeddings?.mode || '?'} (${engine.embeddings?.model || '?'}), neural=${engine.embeddings?.neuralStatus || '?'}, `
    + `catalog ${engine.catalog?.products ?? '?'} products indexed in ${engine.catalog?.buildMs ?? '?'} ms (CPU part of the lazy build), `
    + `visual=${engine.visual?.status || engine.visual?.enabled || '?'}, llm=${engine.llm?.enabled ? `on (${engine.llm.provider || 'provider'})` : 'off'}`);

  const failed = results.filter((r) => r.status >= 400);
  server.close();
  // let fire-and-forget writes (interaction log, stats) finish before the pool closes
  await new Promise((resolve) => { setTimeout(resolve, 2000); });
  const db =require(path.join(FUNCTION_ROOT, 'api', 'db', 'connection'));
  await db.destroy();
  if (failed.length) {
    console.error(`${failed.length} call(s) failed.`);
    process.exit(1);
  }
  console.log('all calls succeeded');
};

main().catch((error) => {
  // never print the error object as a whole: a pg error can carry connection details
  console.error('smoke test crashed:', error.message);
  process.exit(1);
});
