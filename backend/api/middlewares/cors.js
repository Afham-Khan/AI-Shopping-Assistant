const cors = require('cors');

// CORS_ORIGINS = comma separated list of website origins allowed to call the API from a browser, e.g.
//   CORS_ORIGINS=https://zelora.vercel.app,https://*.vercel.app,http://localhost:8080
// "*" inside an entry matches one host label (a preview deployment); a lone "*" allows every website.
// Not set: everything is allowed in development and test, nothing cross-origin is allowed in production.
// Requests without an Origin header (the Android app, curl, health checks) are never blocked by this.

const escapeRegex = (text) => text.replace(/[.+?^${}()|[\]\\]/g, '\\$&');

const toMatcher = (entry) => {
  if (!entry.includes('*')) return (origin) => origin.toLowerCase() === entry.toLowerCase();
  const pattern = new RegExp(`^${entry.split('*').map(escapeRegex).join('[a-z0-9-]+')}$`, 'i');
  return (origin) => pattern.test(origin);
};

const parseOrigins = (raw) => String(raw || '')
  .split(',')
  .map((item) => item.trim().replace(/\/+$/, ''))
  .filter(Boolean);

const createCors = (env = process.env) => {
  const list = parseOrigins(env.CORS_ORIGINS);
  const production = env.NODE_ENV === 'production';
  // preflight answers are cached for 10 minutes so the browser does not repeat them for every request
  const base = { maxAge: 600 };

  if (list.includes('*') || (!list.length && !production)) return cors(base);

  if (!list.length) {
    console.warn('[cors] CORS_ORIGINS is not set: web browsers on other sites are blocked. Set it to your website URL (the Android app is not affected).');
  }
  const matchers = list.map(toMatcher);
  return cors({
    ...base,
    origin: (origin, callback) => callback(null, !origin || matchers.some((matches) => matches(origin))),
  });
};

module.exports = { createCors, parseOrigins };
