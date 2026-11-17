// product comparison: aligned rows with numeric-aware winners + verdict picks and a summary
const models = require('../models/ai.models');
const { toDetail } = require('../../../../helpers/serializers');
const { getCatalog } = require('./retrieval/catalog');
const { money, stars, list } = require('./format');
const { explainProduct } = require('./explain');
const { reviewSummary } = require('./reviews/summary');
const { analyze } = require('./nlu');

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

// the headline figure a shopper reads first: the first unit-tagged number in the value.
// "64 GB (microSD up to 256 GB)" -> 64 GB, "Up to 5 hours listening, 24 hours with charging case" -> 5 h
// (parseQuantity's largest number would crown the expandable storage or the charging-case total instead)
const headlineQuantity = (value) => {
  const s = String(value ?? '').toLowerCase();
  for (const m of s.matchAll(/(\d+(?:\.\d+)?)\s*(tb|gb|mb|mah|mp|hz|inch|"|w|kg|g|ml|l|hours?|h|years?|months?|days?)\b/g)) {
    const [unit, scale] = UNIT_SCALE[m[2]] || [];
    if (unit) return { unit, value: Number.parseFloat(m[1]) * scale };
  }
  return null;
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
    const qty = s.values.map(headlineQuantity);
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

  // differencesOnly support: flag rows whose values are not all the same
  for (const r of rows) r.differs = new Set(r.values.map((v) => String(v).trim().toLowerCase())).size > 1;

  return { rows, verdict: { summary, picks } };
};

// ------------------------------------------------------------------ v2: pros/cons + "for you"

const LEVEL_WORD = [null, 'basic', 'fair', 'good', 'great', 'excellent'];
const keyName = (k) => (/^[A-Z]{2,}$/.test(k) ? k : k.toLowerCase());
const firstSentence = (t) => t.split(/(?<=\.)\s/)[0].replace(/\.$/, '');

// pure: products (catalog rows) + explanations + review summaries -> [{ productId, pros, cons }]
const buildProsCons = (products, rows, explanations, reviews = []) => products.map((p, i) => {
  const pros = [];
  const cons = [];
  const prices = products.map((x) => x.price);
  const distinctPrices = new Set(prices).size > 1;
  if (distinctPrices && p.price === Math.min(...prices)) pros.push(`Cheapest of the ${products.length} at ${money(p.price)}`);
  if (distinctPrices && p.price === Math.max(...prices)) cons.push(`Most expensive at ${money(p.price)}`);
  const ratingRow = rows.find((r) => r.label === 'Rating');
  // a 3.4★ product can top a weak group, but "highest rated" next to "lower rating" reads as a contradiction:
  // below 3.5★ it is only a con, and the pro says it is the best of the group
  if (p.rating_count && p.rating < 3.5) cons.push(`Lower rating (${stars(p.rating)})${ratingRow?.bestIndex === i ? ', though still the best of this group' : ''}`);
  else if (ratingRow?.bestIndex === i) pros.push(`Highest rated (${stars(p.rating)})`);
  if (p.stock <= 0) cons.push('Out of stock right now');
  // spec levels from the explainer: great specs are pros, weak ones cons
  const specs = explanations[i]?.specs || [];
  for (const s of specs.filter((x) => x.level >= 4).sort((a, b) => b.level - a.level).slice(0, 2)) pros.push(`${s.title}: ${firstSentence(s.meaning)}`);
  for (const s of specs.filter((x) => x.level && x.level <= 2).sort((a, b) => a.level - b.level).slice(0, 2)) {
    const word = LEVEL_WORD[s.level];
    cons.push(`${word[0].toUpperCase()}${word.slice(1)} ${keyName(s.key)} (${s.value})`);
  }
  // spec rows it wins outright
  rows.forEach((r) => {
    if (['Price', 'Rating', 'Reviews', 'Brand', 'Availability', 'Discount'].includes(r.label) || r.bestIndex === null) return;
    if (r.bestIndex === i && pros.length < 5) pros.push(`Best ${r.label.toLowerCase()} (${r.values[i]})`);
  });
  const rv = reviews[i];
  if (rv?.pros?.[0]) pros.push(`Reviewers praise the ${rv.pros[0].aspect.toLowerCase()}`);
  if (rv?.cons?.[0]) cons.push(`Some reviewers complain about the ${rv.cons[0].aspect.toLowerCase()}`);
  const dedupe = (a) => [...new Set(a)].slice(0, 4);
  return { productId: p.id, pros: dedupe(pros), cons: dedupe(cons) };
});

// need words -> weights over explained spec keys (+ value / quality)
const NEEDS = {
  gaming: { label: 'gaming', specs: { Processor: 0.3, RAM: 0.2, Graphics: 0.3, Display: 0.2 } },
  camera: { label: 'photography', specs: { 'Rear Camera': 0.6, 'Front Camera': 0.2, Display: 0.1 } },
  battery: { label: 'battery life', specs: { Battery: 0.6, 'Battery Life': 0.6, Charging: 0.2 } },
  work: { label: 'work and study', specs: { RAM: 0.3, Processor: 0.3, 'Battery Life': 0.15, Display: 0.1, Weight: 0.1 } },
  performance: { label: 'performance', specs: { Processor: 0.5, RAM: 0.4, Graphics: 0.2 } },
  lightweight: { label: 'portability', specs: { Weight: 1 } },
  display: { label: 'the screen', specs: { Display: 1 } },
  storage: { label: 'storage', specs: { Storage: 1 } },
  waterproof: { label: 'water resistance', specs: { 'Water Resistance': 1 } },
  fast_charging: { label: 'fast charging', specs: { Charging: 1 } },
  noise_cancelling: { label: 'noise cancelling', specs: { 'Noise Cancellation': 1 } },
  long_lasting: { label: 'a long-lasting scent', specs: { Concentration: 0.5, Longevity: 0.5 } },
  durable: { label: 'durability', specs: { 'Water Resistance': 0.4, Crystal: 0.4 } },
  luxury: { label: 'a premium feel', specs: { Movement: 0.5, Crystal: 0.3 }, quality: 0.3 },
};
const SIMPLE_USERS = new Set(['mom', 'dad', 'grandma', 'grandmother', 'grandpa', 'grandfather', 'aunt', 'uncle']);

const addWeights = (weights, extra) => {
  for (const [k, w] of Object.entries(extra)) weights[k] = (weights[k] || 0) + w;
};

// need text -> { label, weights, value, quality, budget, matched }
const parseNeed = (need, analyzeFn) => {
  const a = analyzeFn(need);
  const e = a.entities;
  const weights = {};
  const labels = [];
  let value = 0.15;
  let quality = 0.15;
  for (const f of e.features) {
    const n = NEEDS[f];
    if (!n) continue;
    labels.push(n.label);
    addWeights(weights, n.specs);
    if (n.quality) quality += n.quality;
  }
  if (e.occasion === 'gym') {
    labels.push('workouts');
    addWeights(weights, { 'Water Resistance': 0.5, Weight: 0.3, Battery: 0.3 });
  } else if (e.occasion === 'travel') {
    labels.push('travel');
    addWeights(weights, { Weight: 0.4, Battery: 0.4, 'Battery Life': 0.4 });
  }
  if (e.recipient && SIMPLE_USERS.has(e.recipient)) {
    labels.push(`your ${e.recipient}`);
    addWeights(weights, { Battery: 0.3, 'Battery Life': 0.3, Display: 0.25, Weight: 0.1 });
    value += 0.35;
  } else if (e.recipient === 'kid') {
    labels.push('a child');
    value += 0.4;
    addWeights(weights, { 'Water Resistance': 0.3, Battery: 0.2 });
  } else if (e.recipient) labels.push(`your ${e.recipient}`);
  if (/\b(?:value|budget|cheap|afford|money)\b/.test(a.normalized) || e.sort === 'price_asc') {
    labels.push('value for money');
    value += 0.5;
  }
  const matched = Boolean(labels.length || e.budget);
  return { label: labels.length ? list([...new Set(labels)]) : String(need).trim(), weights, value, quality, budget: e.budget, matched };
};

const pickForNeed = (products, explanations, needInfo) => {
  const valueRaw = products.map((p) => (Math.max(0.5, (p._bayes ?? p.rating) - 1) ** 2) / Math.sqrt(p.price));
  const maxValue = Math.max(...valueRaw) || 1;
  const specOf = (i, key) => explanations[i]?.specs.find((s) => s.key.toLowerCase() === key.toLowerCase()) || null;
  // only score specs that at least one product actually has
  const keys = Object.keys(needInfo.weights).filter((k) => products.some((_, i) => specOf(i, k)?.level));
  const scores = products.map((p, i) => {
    let spec = 0;
    let wsum = 0;
    const contrib = [];
    for (const k of keys) {
      const lv = specOf(i, k)?.level || 1;
      spec += needInfo.weights[k] * (lv / 5);
      wsum += needInfo.weights[k];
      contrib.push({ key: k, level: lv, weight: needInfo.weights[k] });
    }
    let score = (wsum ? 0.6 * (spec / wsum) : 0) + needInfo.value * (valueRaw[i] / maxValue) + needInfo.quality * (p._quality ?? 0.5);
    if (needInfo.budget?.max && p.price > needInfo.budget.max) score *= 0.4;
    if (p.stock <= 0) score *= 0.7;
    return { productId: p.id, score: +score.toFixed(3), contrib };
  });
  const best = scores.reduce((b, s, i) => (s.score > scores[b].score ? i : b), 0);
  const winner = products[best];
  const top = scores[best].contrib.filter((c) => c.level >= 3).sort((a, b) => b.weight * b.level - a.weight * a.level).slice(0, 2)
    .map((c) => specOf(best, c.key)).filter(Boolean)
    .map((s) => `${keyName(s.key)} (${s.title}, ${s.levelLabel.toLowerCase()})`);
  const extras = [];
  if (needInfo.value >= 0.4 && valueRaw[best] === maxValue) extras.push('it is also the best value for money');
  if (needInfo.budget?.max && winner.price <= needInfo.budget.max) extras.push(`it fits your ${money(needInfo.budget.max)} budget`);
  const reason = needInfo.matched
    ? `For ${needInfo.label}, ${winner.title} is the better fit${top.length ? `: it leads on ${list(top)}` : ''}${extras.length ? `, and ${list(extras)}` : ''}.`
    : `I couldn't map "${needInfo.label}" to specific specs, so this is the best overall pick on rating and value.`;
  return { productId: winner.id, need: needInfo.label, matched: needInfo.matched, reason, scores: scores.map(({ productId, score }) => ({ productId, score })) };
};

// options.need: free text ("for gaming", "for my mom") -> forYou pick
const compareProducts = async (ids, { need = null } = {}) => {
  const unique = [...new Set(ids.map(Number))];
  const [catalog, loaded, breakdowns] = await Promise.all([getCatalog(), models.productsWithImages(unique), models.ratingBreakdowns(unique)]);
  if (loaded.length < 2) return null;
  const rows = loaded.map(({ row }) => ({ ...row, _bayes: catalog.byId.get(row.id)?._bayes ?? row.rating, _quality: catalog.byId.get(row.id)?._quality }));
  const result = buildComparison(rows);
  const explanations = rows.map((r) => explainProduct(r));
  const reviews = await Promise.all(rows.map((r) => reviewSummary(r.id).catch(() => null)));
  const forYou = need ? pickForNeed(rows, explanations, parseNeed(need, analyze)) : null;
  return {
    products: loaded.map(({ row, images }) => toDetail(row, { images, ratingBreakdown: breakdowns.get(row.id) || { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 } })),
    rows: result.rows,
    differencesCount: result.rows.filter((r) => r.differs).length,
    verdict: result.verdict,
    prosCons: buildProsCons(rows, result.rows, explanations, reviews),
    forYou,
  };
};

const pickNames = (comparison) => list(comparison.products.map((p) => p.title));

module.exports = { compareProducts, buildComparison, buildProsCons, parseNeed, pickForNeed, parseQuantity, headlineQuantity, pickNames };
