// dialogue state: slot carry-over, topic-change detection and refinements
const EMPTY_SLOTS = () => ({
  category: null, categories: [], department: null, brands: [], excludeBrands: [], budget: null, gender: null,
  recipient: null, occasion: null, color: null, excludeColors: [], features: [], minRating: null, sort: null,
  keywords: [], terms: [],
});

const initialContext = () => ({ slots: EMPTY_SLOTS(), lastProducts: [], focus: null, offset: 0, pending: null, turns: 0, lastIntent: null });

const loadContext = (raw) => {
  const ctx = { ...initialContext(), ...(raw || {}) };
  ctx.slots = { ...EMPTY_SLOTS(), ...(ctx.slots || {}) };
  return ctx;
};

const overlap = (a, b) => a.some((x) => b.includes(x));
const union = (a, b) => [...new Set([...(a || []), ...(b || [])])];

const hasSearchSlots = (s) => Boolean(s.categories.length || s.department || s.brands.length || s.keywords.length || s.features.length || s.recipient || s.occasion);

const isTopicChange = (prev, e) => {
  if (e.categories.length && prev.categories.length) return !overlap(e.categories, prev.categories);
  if (e.department && prev.department && !e.categories.length) return e.department !== prev.department;
  if (e.categories.length && !prev.categories.length && prev.keywords.length) return true;
  if (!e.categories.length && e.keywords.length && prev.categories.length && !e.brands.length && !e.features.length) return true;
  return false;
};

// mode: 'new' (fresh search), 'merge' (follow-up adds constraints), 'filter' (refine_filter)
const mergeSlots = (prev, e, mode) => {
  let base;
  if (mode === 'new') {
    base = EMPTY_SLOTS();
    // stay in the same department (e.g. dresses -> shoes) keeps who it's for
    if (prev.gender && e.department && e.department === prev.department) base.gender = prev.gender;
    if (prev.recipient && e.department === prev.department) base.recipient = prev.recipient;
  } else {
    base = { ...prev };
  }
  const s = { ...base };
  if (e.categories.length) {
    s.categories = e.categories;
    s.category = e.category;
    s.department = e.department;
  } else if (e.department) {
    s.department = e.department;
    s.categories = [];
    s.category = null;
  }
  if (e.brands.length) s.brands = mode === 'filter' && /\balso\b|\band\b/.test(e._text || '') ? union(prev.brands, e.brands) : e.brands;
  if (e.excludeBrands.length) {
    s.excludeBrands = union(mode === 'new' ? [] : prev.excludeBrands, e.excludeBrands);
    s.brands = s.brands.filter((b) => !s.excludeBrands.includes(b));
  }
  s.excludeBrands = s.excludeBrands.filter((b) => !e.brands.includes(b));
  if (e.budget) s.budget = e.budget;
  if (e.gender) s.gender = e.gender;
  if (e.recipient) s.recipient = e.recipient;
  if (e.occasion) s.occasion = e.occasion;
  if (e.color) {
    s.color = e.color;
    s.excludeColors = (s.excludeColors || []).filter((c) => c !== e.color);
  }
  if (e.excludeColors.length) {
    s.excludeColors = union(mode === 'new' ? [] : prev.excludeColors, e.excludeColors);
    if (s.color && s.excludeColors.includes(s.color)) s.color = null;
  }
  if (e.features.length) s.features = mode === 'new' ? e.features : union(prev.features, e.features);
  if (e.minRating) s.minRating = e.minRating;
  if (e.sort) s.sort = e.sort;
  if (e.keywords.length) s.keywords = mode === 'filter' ? union(prev.keywords, e.keywords) : e.keywords;
  else if (mode === 'new') s.keywords = [];
  if (e.terms?.length) s.terms = e.terms;
  return s;
};

const median = (values) => {
  const a = values.slice().sort((x, y) => x - y);
  return a.length ? a[Math.floor(a.length / 2)] : null;
};

const roundPrice = (v) => (v >= 10000 ? Math.round(v / 1000) * 1000 : Math.round(v / 100) * 100);

const cheaperSlots = (slots, shownPrices) => {
  const ref = Math.min(median(shownPrices) ?? Infinity, slots.budget?.max ?? Infinity);
  const s = { ...slots, sort: slots.sort === 'price_desc' ? null : slots.sort };
  if (Number.isFinite(ref)) s.budget = { min: null, max: roundPrice(ref * 0.8) };
  else s.sort = 'price_asc';
  return s;
};

const premiumSlots = (slots, shownPrices) => {
  const ref = Math.max(median(shownPrices) ?? 0, slots.budget?.min ?? 0);
  const s = { ...slots, sort: slots.sort === 'price_asc' ? null : slots.sort };
  s.budget = ref ? { min: roundPrice(ref * 1.2), max: null } : null;
  if (!ref) s.sort = 'price_desc';
  return s;
};

module.exports = {
  EMPTY_SLOTS, initialContext, loadContext, mergeSlots, isTopicChange, hasSearchSlots, cheaperSlots, premiumSlots, median,
};
