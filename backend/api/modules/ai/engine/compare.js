// product comparison: aligned rows with numeric-aware winners + verdict picks and a summary
const models = require('../models/ai.models');
const { toDetail } = require('../../../../helpers/serializers');
const { getCatalog } = require('./retrieval/catalog');
const { money, stars, list } = require('./format');

const UNIT_SCALE = { tb: ['gb', 1024], gb: ['gb', 1], mb: ['gb', 1 / 1024], mah: ['mah', 1], mp: ['mp', 1], hz: ['hz', 1], inch: ['inch', 1], '"': ['inch', 1], w: ['w', 1], kg: ['g', 1000], g: ['g', 1], ml: ['ml', 1], l: ['ml', 1000], hours: ['h', 1], hour: ['h', 1], h: ['h', 1], years: ['month', 12], year: ['month', 12], months: ['month', 1], month: ['month', 1], days: ['day', 1], day: ['day', 1] };
const LOWER_IS_BETTER = /weight|thickness|depth|price/i;

// largest unit-tagged number in a value, e.g. "Quad: 64 MP + 8 MP" -> { unit: 'mp', value: 64 }
const parseQuantity = (value) => {
  const s = String(value ?? '').toLowerCase();
  let best = null;
  for (const m of s.matchAll(/(\d+(?:\.\d+)?)\s*(tb|gb|mb|mah|mp|hz|inch|"|w|kg|g|ml|l|hours?|h|years?|months?|days?)\b/g)) {
    const [unit, scale] = UNIT_SCALE[m[2]] || [];
    if (!unit) continue;
    const v = Number.parseFloat(m[1]) * scale;
    if (!best) best = { unit, value: v };
    else if (best.unit === unit && v > best.value) best.value = v;
  }
  return best;
};

const winner = (values, lowerBetter = false) => {
  const nums = values.map((v) => (Number.isFinite(v) ? v : null));
  const valid = nums.filter((v) => v !== null);
  if (valid.length < 2 || new Set(valid).size < 2) return null;
  const target = lowerBetter ? Math.min(...valid) : Math.max(...valid);
  return nums.indexOf(target);
};

const returnDays = (p) => {
  const s = String(p.return_policy || '').toLowerCase();
  if (/no return/.test(s)) return 0;
  const m = s.match(/(\d+)\s*(day|month)/);
  return m ? Number(m[1]) * (m[2] === 'month' ? 30 : 1) : null;
};

const bayes = (p) => p._bayes ?? p.rating;

// pure: rows -> comparison table + verdict
const buildComparison = (products) => {
  const rows = [];
  rows.push({ label: 'Price', values: products.map((p) => money(p.price)), bestIndex: winner(products.map((p) => p.price), true) });
  rows.push({ label: 'Rating', values: products.map((p) => (p.rating_count ? stars(p.rating) : 'No ratings')), bestIndex: winner(products.map((p) => (p.rating_count ? bayes(p) : null))) });
  rows.push({ label: 'Reviews', values: products.map((p) => String(p.rating_count)), bestIndex: winner(products.map((p) => p.rating_count)) });
  rows.push({ label: 'Brand', values: products.map((p) => p.brand_name || '—'), bestIndex: null });
  if (products.some((p) => p.discount_percent > 0)) {
    rows.push({ label: 'Discount', values: products.map((p) => (p.discount_percent > 0 ? `${Math.round(p.discount_percent)}% off` : '—')), bestIndex: winner(products.map((p) => p.discount_percent)) });
  }
  rows.push({ label: 'Availability', values: products.map((p) => (p.stock > 0 ? `In stock (${p.stock})` : 'Out of stock')), bestIndex: null });
  rows.push({ label: 'Warranty', values: products.map((p) => p.warranty || '—'), bestIndex: winner(products.map((p) => parseQuantity(p.warranty)?.value ?? (/(no|none)/i.test(p.warranty || '') ? 0 : null))) });
  rows.push({ label: 'Returns', values: products.map((p) => p.return_policy || '—'), bestIndex: winner(products.map(returnDays)) });

  // spec union with case-insensitive keys, most widely shared first
  const keyMap = new Map();
  products.forEach((p, i) => {
    for (const [k, v] of Object.entries(p.specs || {})) {
      const norm = k.trim().toLowerCase();
      if (!keyMap.has(norm)) keyMap.set(norm, { label: k.trim(), values: new Array(products.length).fill(null) });
      keyMap.get(norm).values[i] = String(v);
    }
  });
  const specs = [...keyMap.values()]
    .map((s) => ({ ...s, coverage: s.values.filter(Boolean).length }))
    .sort((a, b) => b.coverage - a.coverage)
    .slice(0, 12);
  for (const s of specs) {
    const qty = s.values.map(parseQuantity);
    const units = new Set(qty.filter(Boolean).map((q) => q.unit));
    const bestIndex = units.size === 1 ? winner(qty.map((q) => q?.value ?? null), LOWER_IS_BETTER.test(s.label)) : null;
    rows.push({ label: s.label, values: s.values.map((v) => v ?? '—'), bestIndex });
  }

  // verdict picks
  const idx = (fn, dir) => products.reduce((best, p, i) => (dir * (fn(p) - fn(products[best])) > 0 ? i : best), 0);
  const valueScore = (p) => (Math.max(0.5, bayes(p) - 1) ** 2) / Math.sqrt(p.price);
  const picks = [];
  const add = (label, i, reason) => picks.push({ label, productId: products[i].id, reason });
  const best = idx(valueScore, 1);
  const top = idx(bayes, 1);
  const cheap = idx((p) => p.price, -1);
  const premium = idx((p) => p.price, 1);
  const pctCheaper = (a, b) => Math.round((1 - products[a].price / products[b].price) * 100);
  add('Best value', best, `${stars(products[best].rating)} for ${money(products[best].price)} — the most rating per rupee${best !== premium ? `, ${pctCheaper(best, premium)}% cheaper than ${products[premium].title}` : ''}`);
  add('Top rated', top, `Highest rating at ${stars(products[top].rating)} from ${products[top].rating_count} reviews`);
  if (cheap !== best) add('Budget pick', cheap, `Lowest price at ${money(products[cheap].price)}`);
  else add('Budget pick', cheap, `Cheapest option and still the best value at ${money(products[cheap].price)}`);
  if (premium !== cheap) add('Premium pick', premium, `Top-end choice at ${money(products[premium].price)}${products[premium].brand_name ? ` from ${products[premium].brand_name}` : ''}`);

  const specWins = new Array(products.length).fill(0);
  rows.forEach((r) => {
    if (r.bestIndex !== null && !['Price', 'Reviews'].includes(r.label)) specWins[r.bestIndex] += 1;
  });
  const leader = specWins.indexOf(Math.max(...specWins));
  const b = products[best];
  const t = products[top];
  let summary = `${b.title} is the best value at ${money(b.price)} with a ${stars(b.rating)} rating.`;
  if (top !== best) summary += ` If you want the highest-rated option, ${t.title} (${stars(t.rating)}) is the pick${t.price > b.price ? ` but costs ${money(t.price - b.price)} more` : ''}.`;
  else summary += ' It is also the highest rated of the group.';
  if (specWins[leader] > 0 && leader !== best) summary += ` On paper, ${products[leader].title} wins the most spec rows (${specWins[leader]}).`;
  if (cheap !== best) summary += ` On a tight budget, ${products[cheap].title} costs just ${money(products[cheap].price)}.`;

  return { rows, verdict: { summary, picks } };
};

const compareProducts = async (ids) => {
  const unique = [...new Set(ids.map(Number))];
  const [catalog, loaded, breakdowns] = await Promise.all([getCatalog(), models.productsWithImages(unique), models.ratingBreakdowns(unique)]);
  if (loaded.length < 2) return null;
  const rows = loaded.map(({ row }) => ({ ...row, _bayes: catalog.byId.get(row.id)?._bayes ?? row.rating }));
  const result = buildComparison(rows);
  return {
    products: loaded.map(({ row, images }) => toDetail(row, { images, ratingBreakdown: breakdowns.get(row.id) || { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 } })),
    rows: result.rows,
    verdict: result.verdict,
  };
};

const pickNames = (comparison) => list(comparison.products.map((p) => p.title));

module.exports = { compareProducts, buildComparison, parseQuantity, pickNames };
