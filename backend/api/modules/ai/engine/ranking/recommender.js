// recommendations: personalized "picked for you", content-based similar items, association-rule bought-together
const models = require('../../models/ai.models');
const L = require('../nlu/lexicon');
const { getCatalog } = require('../retrieval/catalog');
const { getProfile } = require('./personalization');
const { mmr } = require('./ranker');
const { money, stars, plural, list } = require('../format');

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
      products: trending(catalog, limit),
      strategy: 'popularity',
    };
  }
  const { prefs } = profile;
  const budgetMax = prefs.budget?.max || null;
  const gender = prefs.gender && prefs.gender !== 'any' ? prefs.gender : null;
  const exclude = new Set([...profile.purchased, ...profile.inCart]);
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
      const score = 0.32 * Math.max(0, sim) + 0.26 * cat + 0.08 * brand + 0.16 * p._quality + 0.1 * p._popularity + 0.04 * p._discount + 0.04 * inBudget;
      return { p, score, sim, cat, brand, inBudget };
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

const similar = async (productId, limit = 8) => {
  const catalog = await getCatalog();
  const base = catalog.byId.get(Number(productId));
  if (!base) return null;
  const ranked = catalog.products
    .filter((p) => p.id !== base.id && p.stock > 0)
    .map((p) => {
      const sim = Math.max(0, catalog.similarity(base.id, p.id));
      const sameCat = p.category_slug === base.category_slug ? 1 : 0;
      const sameDept = p.department_slug === base.department_slug ? 1 : 0;
      const priceProx = Math.max(0, 1 - Math.abs(Math.log((p.price + 1) / (base.price + 1))) / 1.5);
      const score = 0.55 * sim + 0.17 * sameCat + 0.12 * sameDept + 0.1 * priceProx + 0.06 * p._quality;
      return { p, score, sim, sameCat, priceProx };
    })
    .sort((a, b) => b.score - a.score);
  return mmr(ranked, Math.min(limit, ranked.length), catalog, 0.85, 20).map((r) => card(r.p, r.score, [
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

const boughtTogether = async (productId, limit = 6) => {
  const catalog = await getCatalog();
  const base = catalog.byId.get(Number(productId));
  if (!base) return null;
  const co = await getCooccurrence();
  const row = co.pairCount.get(base.id) || new Map();
  const countA = co.itemCount.get(base.id) || 0;
  const rules = [];
  for (const [b, together] of row) {
    const p = catalog.byId.get(b);
    if (!p || p.stock <= 0 || together < 0.8) continue;
    const confidence = countA ? together / countA : 0;
    const lift = confidence / ((co.itemCount.get(b) || 1) / co.total);
    const sameCatPenalty = p.category_slug === base.category_slug ? 0.7 : 1;
    const score = Math.min(1, (0.6 * confidence + 0.25 * Math.min(1, Math.log1p(lift) / 3) + 0.15 * p._quality) * sameCatPenalty);
    rules.push({ p, score, together, confidence, lift });
  }
  rules.sort((a, b) => b.score - a.score);
  const picked = rules.slice(0, limit).map((r) => card(r.p, r.score, [
    `Bought together by ${plural(Math.round(r.together), 'shopper')}`,
    r.lift >= 1.5 ? `${r.lift.toFixed(1)}× more likely together (lift)` : null,
    `${Math.round(r.confidence * 100)}% of buyers also picked this`,
    qualityReason(r.p),
  ].filter(Boolean)));

  // cold items: complementary categories, preferring accessories cheaper than the base item
  if (picked.length < limit) {
    const have = new Set([base.id, ...picked.map((x) => x.product.id)]);
    const complements = L.COMPLEMENTS[base.category_slug] || [];
    const fill = catalog.products
      .filter((p) => !have.has(p.id) && p.stock > 0 && complements.includes(p.category_slug))
      .map((p) => {
        const rank = complements.indexOf(p.category_slug);
        const cheaper = p.price <= base.price ? 1 : 0.4;
        return { p, score: 0.35 * (1 - rank * 0.2) + 0.3 * p._quality + 0.2 * p._popularity + 0.15 * cheaper };
      })
      .sort((a, b) => b.score - a.score);
    for (const f of capPerCategory(fill, limit - picked.length, 2)) {
      picked.push(card(f.p, f.score * 0.8, [`Goes well with ${base.category_name.toLowerCase()}`, qualityReason(f.p), discountReason(f.p)].filter(Boolean)));
    }
  }
  return picked;
};

module.exports = { recommendations, similar, boughtTogether, trending, getCooccurrence };
