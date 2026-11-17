// Database connection settings, shared by knexfile.js (migrations CLI) and the API.
//
//   DATABASE_URL          full connection string of a hosted database (Neon, ...). Wins over the DB_* values.
//   DATABASE_URL_POOLED   Neon's pooled string (host contains "-pooler"). Used instead of DATABASE_URL when the API
//                         runs serverless (Vercel), where many short-lived instances would otherwise each open their
//                         own connections; also used anywhere when DATABASE_URL is not set. On Vercel you can simply
//                         put the pooled string into DATABASE_URL.
//   DB_SSL                true / false. Forces TLS on or off. Unset = TLS only when the URL asks for it (sslmode=require).
//   DB_POOL_MAX           connections per process (default 5, or 2 per serverless instance)
//   DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME   the local fallback
//
// NODE_ENV=test never reads DATABASE_URL, so a hosted URL left in your shell cannot receive test data.
// Use TEST_DATABASE_URL if you really want the tests to run against a remote database.

const { isServerless } = require('./runtime');

const TLS_MODES = new Set(['require', 'prefer', 'verify-ca', 'verify-full', 'no-verify']);

const explicitFlag = (value) => {
  const v = String(value ?? '').trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(v)) return true;
  if (['0', 'false', 'no', 'off'].includes(v)) return false;
  return undefined;
};

const pick = (...values) => String(values.find((v) => String(v || '').trim()) || '').trim();

const hostedUrl = (env) => {
  if (env.NODE_ENV === 'test') return pick(env.TEST_DATABASE_URL);
  // migrations and scripts keep the direct connection; serverless instances go through Neon's pooler
  return isServerless(env) ? pick(env.DATABASE_URL_POOLED, env.DATABASE_URL) : pick(env.DATABASE_URL, env.DATABASE_URL_POOLED);
};

const sslModeOf = (url) => (/[?&]sslmode=([^&#]*)/i.exec(url) || [])[1]?.toLowerCase();

// node-postgres turns sslmode=... in the URL into its own ssl object, which would override ours,
// so the parameter is removed and the TLS decision is made here, once.
const withoutSslMode = (url) => url.replace(/([?&])sslmode=[^&#]*&?/i, '$1').replace(/[?&]$/, '');

const tlsWanted = (env, url) => {
  const forced = explicitFlag(env.DB_SSL);
  if (forced !== undefined) return forced;
  const mode = url ? sslModeOf(url) : undefined;
  return Boolean(mode) && TLS_MODES.has(mode);
};

const buildConnection = (env = process.env) => {
  const url = hostedUrl(env);
  const ssl = tlsWanted(env, url) ? { rejectUnauthorized: false } : false;
  if (url) return { connectionString: withoutSslMode(url), ssl };
  return {
    host: env.DB_HOST || 'localhost',
    port: Number(env.DB_PORT) || 5432,
    user: env.DB_USER || 'postgres',
    password: env.DB_PASSWORD,
    database: env.DB_NAME || 'cartwise',
    ...(ssl && { ssl }),
  };
};

// serverless: every warm instance keeps its own small pool (module scope, reused across invocations); idle
// connections are closed quickly so a frozen instance does not hold Neon pooler slots for long
const buildPool = (env = process.env) => (isServerless(env)
  ? { min: 0, max: Number(env.DB_POOL_MAX) || 2, idleTimeoutMillis: 10000 }
  : { min: 0, max: Number(env.DB_POOL_MAX) || 5 });

// "ep-xyz.neon.tech/neondb" for logs: never prints the user or the password
const describeTarget = (env = process.env) => {
  const url = hostedUrl(env);
  if (!url) return `${env.DB_HOST || 'localhost'}:${Number(env.DB_PORT) || 5432}/${env.DB_NAME || 'cartwise'}`;
  try {
    const u = new URL(url);
    return `${u.hostname}${u.port ? `:${u.port}` : ''}${u.pathname}`;
  } catch {
    return 'DATABASE_URL (could not be parsed: check it starts with postgresql://)';
  }
};

const usesHostedUrl = (env = process.env) => Boolean(hostedUrl(env));

module.exports = { buildConnection, buildPool, describeTarget, usesHostedUrl, hostedUrl };
