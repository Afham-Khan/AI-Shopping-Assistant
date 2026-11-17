// explainable hybrid ranking: weighted signals -> score in [0,1] + human-readable reasons, mmr diversity
const L = require('../nlu/lexicon');
const { money, stars, truncate, plural } = require('../format');
const { aversion } = require('./personalization');
const A = require('./attributes');

const WEIGHTS = {
  semantic: 0.28, lexical: 0.18, quality: 0.16, popularity: 0.08, discount: 0.04,
  features: 0.12, color: 0.12, occasion: 0.03, personal: 0.1, budget: 0.04, useCase: 0.14, type: 0.1,
};

const colorWords = (color) => L.COLORS[color] || [color];

// any mention of the colour (listed colour, title or colour spec): used for "nothing red" exclusions
const matchesColor = (p, color) => {
  if (A.colorTier(p, color) > 0) return true;
  const hay = `${p.color || ''} ${p.title}`.toLowerCase();
  return colorWords(color).some((w) => new RegExp(`\\b${w}\\b`).test(hay));
};

// how strongly a product supports a requested feature, with a spec/highlight as evidence
const featureMatch = (p, key) => {
  const f = L.FEATURES[key];
  if (!f) return { strength: 0, evidence: null };
  const triggerHit = f.triggers.some((t) => t.length > 3 && p._text.includes(t));
  const hits = f.terms.filter((t) => p._text.includes(t));
  const strength = triggerHit ? 1 : Math.min(1, hits.length * 0.34);
  let evidence = null;
  if (strength > 0) {
    const terms = [...f.triggers, ...f.terms].filter((t) => t.length > 2);
    const spec = Object.entries(p.specs || {}).find(([k, v]) => terms.some((t) => `${k} ${v}`.toLowerCase().includes(t)));
    if (spec) evidence = `${spec[0]}: ${truncate(String(spec[1]), 38)}`;
    else {
      const hl = (p.highlights || []).find((h) => terms.some((t) => h.toLowerCase().includes(t)));
      if (hl) evidence = truncate(hl, 44);
    }
  }
  return { strength, evidence };
};

const occasionMatch = (p, occasion) => {
  const o = L.OCCASIONS[occasion];
  if (!o) return 0;
  const hits = [...o.triggers, ...o.terms].filter((t) => p._text.includes(t)).length;
  return Math.min(1, hits * 0.4);
};

const personalParts = (p, profile, catalog) => {
  if (!profile) return null;
  const v = catalog.vectorOf(p.id);
  let sim = 0;
  if (profile.centroid && v && v.length === profile.centroid.length) {
    for (let k = 0; k < v.length; k += 1) sim += v[k] * profile.centroid[k];
  }
  const cat = profile.catAff.get(p.category_slug) || 0;
  const brand = p.brand_name ? profile.brandAff.get(p.brand_name.toLowerCase()) || 0 : 0;
  const neg = aversion(p, profile, catalog);
  return { sim: Math.max(0, sim), cat, brand, neg, value: Math.max(0, 0.5 * Math.max(0, sim) + 0.35 * cat + 0.15 * brand - 0.3 * neg) };
};

const budgetFit = (price, budget) => {
  if (!budget) return null;
  if (budget.target) return Math.max(0, 1 - Math.abs(price - budget.target) / budget.target);
  if (budget.max) return price <= budget.max ? 0.5 + 0.5 * Math.min(1, price / budget.max) : 0;
  return 1;
};

// ctx: { catalog, slots, semantic: Map, lexical: Map, profile, query? }
// each scored item also carries `fit` (constraint check) and `tier` (constraint rank, see attributes.tierOf)
const scoreAll = (candidates, ctx) => {
  const { slots, semantic, lexical, profile, catalog } = ctx;
  const query = ctx.query || A.queryProfile(slots);
  const maxSem = Math.max(0, ...candidates.map((p) => semantic.get(p.id) || 0));
  const maxLex = Math.max(0, ...candidates.map((p) => lexical.get(p.id) || 0));
  const features = slots.features || [];
  return candidates.map((p) => {
    const parts = {
      quality: p._quality,
      popularity: p._popularity,
      discount: p._discount,
    };
    if (maxSem > 0) parts.semantic = (semantic.get(p.id) || 0) / maxSem;
    if (maxLex > 0) parts.lexical = (lexical.get(p.id) || 0) / maxLex;
    const featureHits = features.map((f) => ({ key: f, ...featureMatch(p, f) }));
    if (features.length) parts.features = featureHits.reduce((s, f) => s + f.strength, 0) / features.length;
    const cfit = A.constraintsFor(p, query);
    if (slots.color) parts.color = (cfit.colorTier || 0) / 3;
    if (cfit.useFit !== null) parts.useCase = cfit.useFit;
    if (query.types.size) parts.type = cfit.typeOk ? 1 : 0;
    if (slots.occasion) parts.occasion = occasionMatch(p, slots.occasion);
    const personal = personalParts(p, profile, catalog);
    if (personal && profile.signalCount) parts.personal = personal.value;
    const fit = budgetFit(p.price, slots.budget);
    if (fit !== null) parts.budget = fit;

    let total = 0;
    let weight = 0;
    for (const [k, v] of Object.entries(parts)) {
      total += WEIGHTS[k] * v;
      weight += WEIGHTS[k];
    }
    return { p, score: weight ? total / weight : 0, parts, featureHits, personal, fit: cfit, tier: A.tierOf(cfit) };
  });
};

const SORTERS = {
  price_asc: (a, b) => a.p.price - b.p.price,
  price_desc: (a, b) => b.p.price - a.p.price,
  rating: (a, b) => b.p._bayes - a.p._bayes,
  popular: (a, b) => b.p.sold_count - a.p.sold_count,
  newest: (a, b) => new Date(b.p.created_at) - new Date(a.p.created_at),
  discount: (a, b) => b.p.discount_percent - a.p.discount_percent,
};

// explicit sort wins among relevant items; the rest follow by score
const orderGroup = (group, sort) => {
  const byScore = group.slice().sort((a, b) => b.score - a.score);
  if (!sort || !SORTERS[sort] || !byScore.length) return byScore;
  const cut = byScore[0].score * 0.6;
  const relevant = byScore.filter((s) => s.score >= cut).sort(SORTERS[sort]);
  const rest = byScore.filter((s) => s.score < cut);
  return [...relevant, ...rest];
};

// groups of equal constraint tier, best tier first (items without a tier form one group)
const byTier = (scored) => {
  const groups = new Map();
  for (const s of scored) {
    const t = s.tier ?? 0;
    if (!groups.has(t)) groups.set(t, []);
    groups.get(t).push(s);
  }
  return [...groups.entries()].sort((a, b) => b[0] - a[0]).map(([, g]) => g);
};

// items meeting more hard constraints (gender, avoided type, named type, colour) always come first;
// score and any explicit sort only decide the order inside one constraint tier
const order = (scored, sort) => byTier(scored).flatMap((g) => orderGroup(g, sort));

// maximal marginal relevance: trade relevance for novelty so results aren't near-duplicates.
// diversity never beats constraints: a lower-tier item is picked only when no higher-tier item is left
const mmr = (ranked, k, catalog, lambda = 0.75, pool = 30) => {
  const candidates = ranked.slice(0, Math.max(k, pool));
  const selected = [];
  while (selected.length < k && candidates.length) {
    let bestIdx = -1;
    let bestVal = -Infinity;
    const topTier = Math.max(...candidates.map((c) => c.tier ?? 0));
    candidates.forEach((c, i) => {
      if ((c.tier ?? 0) < topTier) return;
      const maxSim = selected.length ? Math.max(...selected.map((s) => catalog.similarity(c.p.id, s.p.id))) : 0;
      const val = lambda * c.score - (1 - lambda) * maxSim;
      if (val > bestVal) {
        bestVal = val;
        bestIdx = i;
      }
    });
    if (bestIdx < 0) bestIdx = candidates.findIndex((c) => (c.tier ?? 0) === topTier);
    selected.push(candidates.splice(bestIdx, 1)[0]);
  }
  return selected;
};

// ctx adds { recipient, sameAs } for wording
const reasonsFor = (s, ctx) => {
  const { p } = s;
  const { slots = {}, catalog, profile } = ctx;
  const reasons = [];
  const b = slots.budget;
  if (b?.max && p.price <= b.max) reasons.push(`Within your ${money(b.max)} budget`);
  else if (b?.min && !b.max && p.price >= b.min) reasons.push(`Above ${money(b.min)} as requested`);
  for (const f of s.featureHits || []) {
    if (f.strength < 0.34) continue;
    const label = L.FEATURES[f.key]?.label || f.key;
    reasons.push(f.evidence ? `Great for ${label}: ${f.evidence}` : `Suited for ${label}`);
    if (reasons.length >= 3) break;
  }
  if (slots.brands?.length && p.brand_name && slots.brands.includes(p.brand_name.toLowerCase())) reasons.push(`${p.brand_name}, as you asked`);
  if (slots.color && s.parts.color) reasons.push(s.fit?.colorTier === 1 ? `Has ${slots.color} accents` : `Comes in ${p.color || slots.color}`);
  if (p.rating >= 4 && p.rating_count >= 3) reasons.push(`Rated ${stars(p.rating)} by ${plural(p.rating_count, 'shopper')}`);
  if (p.discount_percent >= 10 && p.compare_at_price) reasons.push(`${Math.round(p.discount_percent)}% off — save ${money(p.compare_at_price - p.price)}`);
  if (s.personal) {
    if (s.personal.sim > 0.6 && profile?.recent?.length) reasons.push('Similar to items you viewed');
    else if (s.personal.cat >= 0.6) reasons.push(`Matches your interest in ${p.category_name}`);
    if (s.personal.brand >= 0.7 && p.brand_name) reasons.push(`You like ${p.brand_name}`);
  }
  if (slots.occasion && s.parts.occasion > 0) reasons.push(`Nice pick for ${slots.occasion === 'eid' ? 'Eid' : `a ${slots.occasion}`}`);
  if (catalog && p.sold_count >= catalog.bestsellerCut) reasons.push(`Bestseller — ${p.sold_count} sold`);
  if (!reasons.length) reasons.push(p.rating_count ? `${stars(p.rating)} average rating` : `In ${p.category_name}`);
  return [...new Set(reasons)].slice(0, 4);
};

module.exports = { scoreAll, order, byTier, mmr, reasonsFor, featureMatch, matchesColor, budgetFit, WEIGHTS, SORTERS };
