// named-product resolver: "is the iphone 13 waterproof?" / "how much ram does the macbook pro have?"
// finds the catalog product a question is about, without needing a product list on screen first.
const { tokenize, baseClean } = require('../nlu/normalizer');
const { BRAND_ALIASES } = require('../nlu/vocab');

const MODEL_SUFFIX = new Set(['pro', 'max', 'plus', 'mini', 'ultra', 'lite', 'se', 'fe', 'air', 'neo']);
const cache = new WeakMap();

const entriesFor = (catalog) => {
  if (cache.has(catalog)) return cache.get(catalog);
  const entries = catalog.products.map((p) => ({
    p,
    tokens: [...new Set(tokenize(baseClean(p.title)))],
    brand: tokenize(baseClean(p.brand_name || '')),
  }));
  cache.set(catalog, entries);
  return entries;
};

// tokens: normalized query tokens; categories: categories the nlu found (used to drop accessories for "iphone")
const findNamedProduct = (tokens, catalog, categories = []) => {
  const set = new Set(tokens);
  const impliedBrands = new Set(tokens.filter((t) => BRAND_ALIASES[t]?.brand).map((t) => BRAND_ALIASES[t].brand));
  const queryNums = tokens.filter((t) => /^\d+$/.test(t) && Number(t) < 100);
  let best = null;
  for (const entry of entriesFor(catalog)) {
    const { p, tokens: tt, brand } = entry;
    const matched = tt.filter((t) => set.has(t) || (brand.includes(t) && impliedBrands.has(brand.join(' '))));
    if (matched.length < 2) continue;
    const anchor = matched.some((t) => /\d/.test(t) || t.length <= 2 || BRAND_ALIASES[t] || brand.includes(t));
    if (!anchor) continue;
    const head = tt.slice(0, 4);
    const coverage = head.filter((t) => matched.includes(t)).length / head.length;
    if (coverage < 0.5) continue;
    // "iphone 13" must not resolve to "iPhone 6"
    const titleNums = tt.filter((t) => /^\d+$/.test(t) && Number(t) < 100);
    if (queryNums.length && titleNums.length && !queryNums.some((n) => titleNums.includes(n))) continue;
    // "is the iphone good" should not land on an iPhone charger
    if (categories.length && !categories.includes(p.category_slug) && !tt.some((t) => set.has(t) && !BRAND_ALIASES[t] && !brand.includes(t) && !/\d/.test(t))) continue;
    const score = matched.length + coverage + (categories.includes(p.category_slug) ? 0.5 : 0);
    if (!best || score > best.score) best = { entry, matched, score };
  }
  if (!best) return null;
  const { p, tokens: tt } = best.entry;
  const missing = tt.filter((t) => !best.matched.includes(t));
  const partial = missing.length > 0 && missing.every((t) => MODEL_SUFFIX.has(t));
  const asked = partial ? p.title.split(/\s+/).filter((w) => !missing.includes(w.toLowerCase())).join(' ') : null;
  return { product: p, partial, asked, exact: missing.length === 0 };
};

module.exports = { findNamedProduct };
