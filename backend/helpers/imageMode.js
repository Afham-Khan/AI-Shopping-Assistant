// Where product images live.
//   cdn    keep the original absolute https://cdn.dummyjson.com/... URLs (nothing to host; what a deployed API needs)
//   local  copies downloaded by `npm run images:cache` into uploads/products and served by this API (offline demos)
//
// IMAGE_MODE decides. When unset: production, or any run against a hosted DATABASE_URL, means cdn; otherwise local.
const MODES = ['cdn', 'local'];

const imageMode = (env = process.env) => {
  const raw = String(env.IMAGE_MODE || '').trim().toLowerCase();
  if (raw) {
    if (!MODES.includes(raw)) throw new Error(`IMAGE_MODE must be "cdn" or "local" (got "${env.IMAGE_MODE}")`);
    return raw;
  }
  return env.NODE_ENV === 'production' || String(env.DATABASE_URL || '').trim() ? 'cdn' : 'local';
};

module.exports = { imageMode };
