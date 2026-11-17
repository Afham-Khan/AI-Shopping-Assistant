// hybrid retrieval: hard filters (with honest progressive relaxation) + bm25 + semantic scores -> ranked items
const L = require('../nlu/lexicon');
const { stem } = require('../nlu/normalizer');
const { getCatalog } = require('./catalog');
const { scoreAll, order, mmr, reasonsFor, matchesColor } = require('../ranking/ranker');
const { money, list } = require('../format');

const opposite = { men: 'women', women: 'men' };

const categoryLabel = (catalog, slugs) =>
  list(slugs.map((s) => catalog.taxonomy.find((c) => c.slug === s)?.name || s), 'or');

const applyFilters = (products, f) =>
  products.filter((p) => {
    if (f.inStock && p.stock <= 0) return false;
    if (f.categories?.length && !f.categories.includes(p.category_slug)) return false;
    if (!f.categories?.length && f.department && p.department_slug !== f.department) return false;
    const brand = (p.brand_name || '').toLowerCase();
    if (f.brands?.length && !f.brands.includes(brand)) return false;
    if (f.excludeBrands?.length && f.excludeBrands.includes(brand)) return false;
    if (f.minPrice != null && p.price < f.minPrice) return false;
    if (f.maxPrice != null && p.price > f.maxPrice) return false;
    if (f.minRating != null && p.rating < f.minRating) return false;
    if (f.gender && p.gender === opposite[f.gender]) return false;
    if (f.excludeColors?.some((c) => matchesColor(p, c))) return false;
    if (f.excludeIds?.size && f.excludeIds.has(p.id)) return false;
    return true;
  });

const filtersFromSlots = (slots, excludeIds = []) => ({
  inStock: true,
  categories: slots.categories?.length ? slots.categories : slots.category ? [slots.category] : [],
  department: slots.department || null,
  brands: slots.brands || [],
  excludeBrands: slots.excludeBrands || [],
  minPrice: slots.budget?.min ?? null,
  maxPrice: slots.budget?.max ?? null,
  minRating: slots.minRating ?? null,
  gender: slots.gender && slots.gender !== 'any' ? slots.gender : null,
  excludeColors: slots.excludeColors || [],
  excludeIds: new Set(excludeIds),
});

// weighted bm25 query: explicit keywords > feature/occasion/color expansion terms
const lexicalTerms = (slots) => {
  const terms = new Map();
  const add = (t, w) => {
    for (const part of String(t).toLowerCase().split(/\s+/)) {
      const s = stem(part);
      if (s.length > 1 && !L.STOPWORDS.has(s)) terms.set(s, Math.max(terms.get(s) || 0, w));
    }
  };
  for (const k of slots.keywords || []) add(k, 1);
  for (const k of slots.terms || []) add(k, 0.6);
  for (const f of slots.features || []) {
    for (const t of L.FEATURES[f]?.triggers || []) add(t, 0.8);
    for (const t of L.FEATURES[f]?.terms || []) add(t, 0.35);
  }
  if (slots.occasion) for (const t of L.OCCASIONS[slots.occasion]?.triggers || []) add(t, 0.5);
  if (slots.color) for (const t of L.COLORS[slots.color] || []) add(t, 0.5);
  return terms;
};

// natural-language query for the embedding model
const semanticQuery = (slots, catalog) => {
  const parts = [];
  if (slots.color) parts.push(slots.color);
  for (const f of slots.features || []) parts.push(L.FEATURES[f]?.label || f);
  parts.push(...(slots.keywords || []));
  if (slots.categories?.length) parts.push(categoryLabel(catalog, slots.categories));
  if (slots.gender) parts.push(`for ${slots.gender}`);
  if (slots.occasion) parts.push(`for ${slots.occasion}`);
  return parts.join(' ').trim();
};

// ladder of relaxations tried in order when filters leave nothing
const RELAX_STEPS = [
  {
    key: 'minRating',
    when: (f) => f.minRating != null,
    apply: (f) => ({ ...f, minRating: null }),
    message: (f) => `Nothing rated ${f.minRating}★+ matched, so I included lower-rated options.`,
  },
  {
    key: 'budget',
    when: (f) => f.maxPrice != null || f.minPrice != null,
    apply: (f) => ({ ...f, maxPrice: null, minPrice: null }),
    message: (f, found) => {
      if (f.maxPrice != null) {
        const above = found.filter((p) => p.price > f.maxPrice).map((p) => p.price);
        const closest = above.length ? Math.min(...above) : null;
        return closest
          ? `Nothing under ${money(f.maxPrice)} — the closest options start at ${money(closest)}.`
          : `Nothing matched under ${money(f.maxPrice)}, so I widened the price range.`;
      }
      return `Nothing above ${money(f.minPrice)} — here are the most premium options available.`;
    },
    sort: (f) => (f.maxPrice != null ? 'price_asc' : 'price_desc'),
  },
  {
    key: 'brands',
    when: (f) => f.brands.length > 0,
    apply: (f) => ({ ...f, brands: [] }),
    message: (f) => `No ${list(f.brands.map((b) => b.replace(/\b\w/g, (m) => m.toUpperCase())), 'or')} products match that, so here are alternatives from other brands.`,
  },
  {
    key: 'gender',
    when: (f) => f.gender != null,
    apply: (f) => ({ ...f, gender: null }),
    message: () => 'I widened the search beyond gender-specific items.',
  },
  {
    key: 'excludeColors',
    when: (f) => f.excludeColors.length > 0,
    apply: (f) => ({ ...f, excludeColors: [] }),
    message: () => 'Every match came in the colour you wanted to avoid, so I kept a few anyway.',
  },
  {
    key: 'category',
    when: (f) => f.categories.length > 0,
    apply: (f, catalog) => {
      const dept = catalog.taxonomy.find((c) => c.slug === f.categories[0])?.departmentSlug || null;
      return { ...f, categories: [], department: dept };
    },
    message: (f, found, catalog) => `I couldn't find that in ${categoryLabel(catalog, f.categories)}, so I looked across the whole department.`,
  },
];

// slots: dialogue/nlu slots; options: { profile, limit, offset, excludeIds, diversity, keywordGate }
const retrieve = async (slots, options = {}) => {
  const { profile = null, limit = 6, offset = 0, excludeIds = [], diversity = true, perCategoryCap = null } = options;
  const catalog = await getCatalog();
  const lexical = catalog.bm25.score(lexicalTerms(slots));
  const sem = await catalog.semanticScores(semanticQuery(slots, catalog));

  let filters = filtersFromSlots(slots, excludeIds);
  let candidates = applyFilters(catalog.products, filters);
  const relaxed = [];
  let forcedSort = null;

  // open-ended keyword queries ("mascara", "pizza") must actually match something
  const scoped = filters.categories.length || filters.department || filters.brands.length;
  const gateTerms = [...(slots.keywords || [])];
  let noMatch = false;
  if (!scoped && gateTerms.length) {
    const semFloor = sem.mode === 'neural' ? 0.4 : 0.15;
    const gated = candidates.filter((p) => (lexical.get(p.id) || 0) > 0 || (sem.scores.get(p.id) || 0) >= semFloor);
    if (!gated.length) noMatch = true;
    candidates = gated;
  }

  if (!candidates.length && !noMatch) {
    for (const step of RELAX_STEPS) {
      if (!step.when(filters)) continue;
      const before = filters;
      filters = step.apply(filters, catalog);
      candidates = applyFilters(catalog.products, filters);
      if (candidates.length) {
        relaxed.push({ type: step.key, message: step.message(before, candidates, catalog) });
        if (step.sort && !slots.sort) forcedSort = step.sort(before);
        break;
      }
      relaxed.push({ type: step.key, message: null });
    }
  }
  const relaxations = relaxed.filter((r) => r.message);

  const ctx = { catalog, slots, semantic: sem.scores, lexical, profile };
  const scored = scoreAll(candidates, ctx);
  let ranked = order(scored, slots.sort || forcedSort);
  if (diversity && !slots.sort && !forcedSort && ranked.length > limit) {
    const head = mmr(ranked, Math.min(ranked.length, offset + limit), catalog);
    const headIds = new Set(head.map((h) => h.p.id));
    ranked = [...head, ...ranked.filter((r) => !headIds.has(r.p.id))];
  }
  if (perCategoryCap) {
    const counts = new Map();
    const capped = [];
    const overflow = [];
    for (const r of ranked) {
      const c = counts.get(r.p.category_slug) || 0;
      (c < perCategoryCap ? capped : overflow).push(r);
      counts.set(r.p.category_slug, c + 1);
    }
    ranked = [...capped, ...overflow];
  }
  const page = ranked.slice(offset, offset + limit).map((s) => ({
    product: s.p,
    score: +Math.min(1, s.score).toFixed(3),
    parts: s.parts,
    reasons: reasonsFor(s, ctx),
  }));
  return {
    items: page,
    total: ranked.length,
    relaxed: relaxations,
    fallback: relaxations.length > 0,
    noMatch,
    mode: sem.mode,
    effectiveFilters: { ...filters, excludeIds: undefined },
    catalog,
  };
};

module.exports = { retrieve, applyFilters, filtersFromSlots, lexicalTerms, semanticQuery, categoryLabel };
