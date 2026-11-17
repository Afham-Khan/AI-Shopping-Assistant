// user profile from implicit + explicit signals: category/brand affinity, taste centroid, price level
const models = require('../../models/ai.models');

const TYPE_WEIGHTS = { purchase: 3, cart: 2, wishlist: 2, ai_click: 1.5, click: 1, view: 0.7 };
const HALF_LIFE_DAYS = 21;
const TTL_MS = 60 * 1000;
const cache = new Map();

const decay = (date) => {
  const days = (Date.now() - new Date(date).getTime()) / 86400000;
  return 0.5 ** (Math.max(0, days) / HALF_LIFE_DAYS);
};

const normalizeMap = (map) => {
  const max = Math.max(0, ...map.values());
  if (!max) return map;
  for (const [k, v] of map) map.set(k, v / max);
  return map;
};

const buildProfile = (signals, catalog) => {
  const { user, interactions, wishlist, cart, purchases } = signals;
  const prefs = user?.preferences || {};
  const weights = new Map();
  const add = (id, w) => {
    if (catalog.byId.has(id)) weights.set(id, (weights.get(id) || 0) + w);
  };
  for (const i of interactions) add(i.product_id, (TYPE_WEIGHTS[i.type] || 0.5) * decay(i.created_at));
  for (const w of wishlist) add(w.product_id, TYPE_WEIGHTS.wishlist * decay(w.created_at));
  for (const c of cart) add(c.product_id, TYPE_WEIGHTS.cart * decay(c.created_at));
  for (const p of purchases) add(p.product_id, TYPE_WEIGHTS.purchase * decay(p.created_at));

  const catAff = new Map();
  const brandAff = new Map();
  let centroid = null;
  let totalW = 0;
  const prices = [];
  for (const [id, w] of weights) {
    const p = catalog.byId.get(id);
    catAff.set(p.category_slug, (catAff.get(p.category_slug) || 0) + w);
    if (p.brand_name) brandAff.set(p.brand_name.toLowerCase(), (brandAff.get(p.brand_name.toLowerCase()) || 0) + w);
    const v = catalog.vectorOf(id);
    if (v) {
      if (!centroid) centroid = new Float32Array(v.length);
      for (let k = 0; k < v.length; k += 1) centroid[k] += v[k] * w;
      totalW += w;
    }
    prices.push(p.price);
  }
  if (centroid && totalW) {
    const norm = Math.sqrt(centroid.reduce((s, x) => s + x * x, 0)) || 1;
    for (let k = 0; k < centroid.length; k += 1) centroid[k] /= norm;
  }
  normalizeMap(catAff);
  normalizeMap(brandAff);
  // explicit interests from onboarding blend in as a floor
  for (const slug of prefs.interests || []) catAff.set(slug, Math.max(catAff.get(slug) || 0, 0.6));

  const recent = interactions.filter((i) => ['view', 'click', 'wishlist', 'cart', 'ai_click'].includes(i.type))
    .map((i) => i.product_id).filter((id, idx, arr) => arr.indexOf(id) === idx && catalog.byId.has(id)).slice(0, 10);
  prices.sort((a, b) => a - b);
  return {
    userId: user?.id || null,
    firstName: (user?.name || '').split(' ')[0] || null,
    prefs,
    catAff,
    brandAff,
    centroid,
    purchased: new Set(purchases.map((p) => p.product_id)),
    inCart: new Set(cart.map((c) => c.product_id)),
    recent,
    signalCount: weights.size,
    hasSignals: weights.size >= 2,
    medianPrice: prices.length ? prices[Math.floor(prices.length / 2)] : null,
    topCategories: [...catAff].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([slug]) => slug),
    topBrands: [...brandAff].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([b]) => b),
  };
};

const getProfile = async (userId, catalog) => {
  if (!userId) return null;
  const hit = cache.get(userId);
  if (hit && Date.now() - hit.at < TTL_MS && hit.signature === catalog.signature) return hit.profile;
  const signals = await models.userSignals(userId);
  if (!signals.user) return null;
  const profile = buildProfile(signals, catalog);
  cache.set(userId, { at: Date.now(), profile, signature: catalog.signature });
  return profile;
};

const invalidate = (userId) => cache.delete(userId);

module.exports = { getProfile, buildProfile, invalidate, TYPE_WEIGHTS };
