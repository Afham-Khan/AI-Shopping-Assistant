// recommendations: personalized "picked for you", content-based similar items, association-rule bought-together
const models = require('../../models/ai.models');
const { getCatalog } = require('../retrieval/catalog');
const { getProfile, aversion } = require('./personalization');
const { mmr } = require('./ranker');
const { money, stars, plural, list } = require('../format');
const { attrsOf } = require('./attributes');
const { genderOf, wrongGender, isKidsItem, sameSubtype, complementaryFor } = require('../complements');

const COOC_TTL_MS = 10 * 60 * 1000;
let cooc = null;

const card = (p, score, reasons) => ({ product: p, score: +Math.max(0, Math.min(1, score)).toFixed(3), reasons: [...new Set(reasons)].slice(0, 4) });

const qualityReason = (p) => (p.rating >= 4 && p.rating_count >= 3 ? `Rated ${stars(p.rating)} by ${plural(p.rating_count, 'shopper')}` : null);
const discountReason = (p) => (p.discount_percent >= 10 && p.compare_at_price ? `${Math.round(p.discount_percent)}% off right now` : null);

// cap items per category so the rail is varied
const capPerCategory = (ranked, k, cap) => {
  const counts = new Map();
  const out = [];
  for (const r of ranked) {
    const c = counts.get(r.p.category_slug) || 0;
    if (c >= cap) continue;
    counts.set(r.p.category_slug, c + 1);
    out.push(r);
    if (out.length >= k) break;
  }
  return out;
};

const trending = (catalog, limit, exclude = new Set()) => {
  const ranked = catalog.products
    .filter((p) => p.stock > 0 && !exclude.has(p.id))
    .map((p) => ({ p, score: 0.5 * p._quality + 0.4 * p._popularity + 0.1 * p._discount }))
    .sort((a, b) => b.score - a.score);
  return capPerCategory(ranked, limit, 2).map((r) => card(r.p, r.score, [
    r.p.sold_count >= catalog.bestsellerCut ? `Trending — ${r.p.sold_count} sold` : null,
    qualityReason(r.p),
    discountReason(r.p),
  ].filter(Boolean).concat(`Popular in ${r.p.category_name}`)));
};

const recommendations = async (userId, limit = 10) => {
  const catalog = await getCatalog();
  const profile = userId ? await getProfile(userId, catalog) : null;
  if (!profile || (!profile.hasSignals && !(profile.prefs.interests || []).length)) {
    return {
      title: 'Trending now',
      subtitle: 'Top rated and best-selling picks across Zelora',
      products: trending(catalog, limit, profile?.passed || new Set()),
      strategy: 'popularity',
    };
  }
  const { prefs } = profile;
  const budgetMax = prefs.budget?.max || null;
  const gender = prefs.gender && prefs.gender !== 'any' ? prefs.gender : null;
  const exclude = new Set([...profile.purchased, ...profile.inCart, ...(profile.passed || [])]);
  const scored = catalog.products
    .filter((p) => p.stock > 0 && !exclude.has(p.id))
    .filter((p) => !(gender && p.gender === (gender === 'men' ? 'women' : 'men')))
    .map((p) => {
      const v = catalog.vectorOf(p.id);
      let sim = 0;
      if (profile.centroid && v && v.length === profile.centroid.length) for (let k = 0; k < v.length; k += 1) sim += v[k] * profile.centroid[k];
      const cat = profile.catAff.get(p.category_slug) || 0;
      const brand = p.brand_name ? profile.brandAff.get(p.brand_name.toLowerCase()) || 0 : 0;
      const inBudget = budgetMax ? (p.price <= budgetMax ? 1 : Math.max(0, 1 - (p.price - budgetMax) / budgetMax)) : 1;
      // swiped-away taste (discover "pass") pulls the score down
      const neg = aversion(p, profile, catalog);
      const score = 0.32 * Math.max(0, sim) + 0.26 * cat + 0.08 * brand + 0.16 * p._quality + 0.1 * p._popularity + 0.04 * p._discount + 0.04 * inBudget - 0.25 * neg;
      return { p, score, sim, cat, brand, inBudget, neg };
    })
    .sort((a, b) => b.score - a.score);
  const diverse = capPerCategory(mmr(scored, Math.min(scored.length, limit * 2), catalog, 0.7), limit, 3);
  const recentTitles = profile.recent.slice(0, 1).map((id) => catalog.byId.get(id)?.title).filter(Boolean);
  const products = diverse.map((r) => card(r.p, r.score, [
    r.sim > 0.55 && recentTitles.length ? 'Similar to items you viewed' : null,
    r.cat >= 0.6 ? `Matches your interest in ${r.p.category_name}` : null,
    r.brand >= 0.7 ? `You like ${r.p.brand_name}` : null,
    budgetMax && r.p.price <= budgetMax ? `Within your ${money(budgetMax)} budget` : null,
    qualityReason(r.p),
    discountReason(r.p),
  ].filter(Boolean).concat(`Popular in ${r.p.category_name}`)));
  const catNames = profile.topCategories.map((s) => catalog.taxonomy.find((c) => c.slug === s)?.name).filter(Boolean).slice(0, 2);
  return {
    title: profile.firstName ? `Picked for you, ${profile.firstName}` : 'Picked for you',
    subtitle: profile.hasSignals
      ? `Based on what you viewed, saved and bought${catNames.length ? ` — mostly ${list(catNames)}` : ''}`
      : `Based on your interests: ${list(catNames)}`,
    products,
    strategy: profile.hasSignals ? 'hybrid-personalized' : 'cold-start-preferences',
  };
};

// how close a candidate is to the base as a *kind* of product: 0 same category, 1 same department and the same
// product type (shared tag or derived type: sneaker/sneaker, sofa/bed both "furniture" tags), 2 same department only
// when the embeddings say it is very close, null otherwise (a kitchen tray is never "similar" to an office chair)
const SIMILAR_CROSS_CATEGORY_SIM = 0.6;
const similarTier = (base, p, sim) => {
  if (p.category_slug === base.category_slug) return 0;
  if (!base.department_slug || p.department_slug !== base.department_slug) return null;
  const baseTypes = attrsOf(base).types;
  if (sameSubtype(base, p) || [...attrsOf(p).types].some((t) => t !== 'kids' && baseTypes.has(t))) return 1;
  return sim >= SIMILAR_CROSS_CATEGORY_SIM ? 2 : null;
};

const similar = async (productId, limit = 8) => {
  const catalog = await getCatalog();
  const base = catalog.byId.get(Number(productId));
  if (!base) return null;
  const gender = genderOf(base);
  const kidsBase = isKidsItem(base);
  const ranked = catalog.products
    .filter((p) => p.id !== base.id && p.stock > 0)
    // the same audience: a men's watch never gets a women's watch, an adult item never a child's
    .filter((p) => !(gender !== 'unisex' && wrongGender(p, gender)) && isKidsItem(p) === kidsBase)
    .map((p) => {
      const sim = Math.max(0, catalog.similarity(base.id, p.id));
      const tier = similarTier(base, p, sim);
      if (tier === null) return null;
      const sameCat = tier === 0 ? 1 : 0;
      const priceProx = Math.max(0, 1 - Math.abs(Math.log((p.price + 1) / (base.price + 1))) / 1.5);
      const score = 0.55 * sim + 0.17 * sameCat + 0.12 + 0.1 * priceProx + 0.06 * p._quality;
      return { p, score, sim, sameCat, priceProx, tier };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);
  // embedding similarity orders each tier (with MMR for variety); a closer tier always comes first, and an
  // honest short list beats padding it with other kinds of products
  const picked = [];
  for (const tier of [0, 1, 2]) {
    const pool = ranked.filter((r) => r.tier === tier);
    const k = Math.min(limit - picked.length, pool.length);
    if (k > 0) picked.push(...mmr(pool, k, catalog, 0.85, 20));
  }
  return picked.map((r) => card(r.p, r.score, [
    r.sim > 0.5 ? `Similar to ${base.title}` : null,
    r.sameCat ? `Also in ${r.p.category_name}` : `Related ${r.p.category_name}`,
    r.priceProx > 0.75 ? `Similar price (${money(r.p.price)})` : r.p.price < base.price ? `${money(base.price - r.p.price)} cheaper` : null,
    p0Brand(base, r.p),
    qualityReason(r.p),
  ].filter(Boolean)));
};

const p0Brand = (a, b) => (a.brand_name && a.brand_name === b.brand_name ? `Also by ${b.brand_name}` : null);

// weighted baskets: orders 1.0, carts 0.6, wishlists 0.4 -> support/confidence/lift
const buildCooccurrence = async () => {
  const { orders, carts, wishlists } = await models.basketRows();
  const baskets = new Map();
  const addAll = (rows, prefix, weight) => {
    for (const r of rows) {
      const key = `${prefix}:${r.basket}`;
      if (!baskets.has(key)) baskets.set(key, { weight, items: new Set() });
      baskets.get(key).items.add(r.product_id);
    }
  };
  addAll(orders, 'o', 1);
  addAll(carts, 'c', 0.6);
  addAll(wishlists, 'w', 0.4);
  const itemCount = new Map();
  const pairCount = new Map();
  let total = 0;
  for (const { weight, items } of baskets.values()) {
    total += weight;
    const arr = [...items];
    for (const a of arr) itemCount.set(a, (itemCount.get(a) || 0) + weight);
    if (arr.length < 2 || arr.length > 30) continue;
    for (const a of arr) {
      if (!pairCount.has(a)) pairCount.set(a, new Map());
      const row = pairCount.get(a);
      for (const b of arr) if (a !== b) row.set(b, (row.get(b) || 0) + weight);
    }
  }
  return { at: Date.now(), total, itemCount, pairCount, baskets: baskets.size };
};

const getCooccurrence = async () => {
  if (!cooc || Date.now() - cooc.at > COOC_TTL_MS) cooc = await buildCooccurrence();
  return cooc;
};

// raw association rules for the base item (support/confidence/lift over weighted baskets), best first.
// the baskets are noisy, so these are only a signal: boughtTogether filters them through goesWith.
const associationRules = async (base, catalog) => {
  const co = await getCooccurrence();
  const row = co.pairCount.get(base.id) || new Map();
  const countA = co.itemCount.get(base.id) || 0;
  const rules = [];
  for (const [b, together] of row) {
    const p = catalog.byId.get(b);
    if (!p || p.stock <= 0 || together < 0.8) continue;
    const confidence = countA ? together / countA : 0;
    const lift = confidence / ((co.itemCount.get(b) || 1) / co.total);
    const score = Math.min(1, 0.6 * confidence + 0.25 * Math.min(1, Math.log1p(lift) / 3) + 0.15 * p._quality);
    rules.push(card(p, score, [
      `Bought together by ${plural(Math.round(together), 'shopper')}`,
      lift >= 1.5 ? `${lift.toFixed(1)}× more likely together (lift)` : null,
      `${Math.round(confidence * 100)}% of buyers also picked this`,
      qualityReason(p),
    ].filter(Boolean)));
  }
  return rules.sort((a, b) => b.score - a.score);
};

// items that genuinely go with the base: co-purchase picks that pass goesWith (compatible, right audience, not a
// substitute such as another phone or pair of sneakers), then the best complementary products. When nothing in the
// catalog really goes with it the list is empty, so the rail is hidden instead of showing unrelated items.
const boughtTogether = async (productId, limit = 6) => {
  const catalog = await getCatalog();
  const base = catalog.byId.get(Number(productId));
  if (!base) return null;
  const seed = await associationRules(base, catalog);
  return complementaryFor(base, catalog, { limit, seed });
};

module.exports = { recommendations, similar, boughtTogether, associationRules, trending, getCooccurrence };
