// discover: swipe deck (personalized + exploration, passes are negative feedback), taste summary from
// swipes, per-department "reels" stories and the illustrated room zones on Home.
const crypto = require('crypto');
const { getCatalog } = require('./retrieval/catalog');
const { getProfile, aversion } = require('./ranking/personalization');
const { money, plural, stars } = require('./format');

const clamp01 = (v) => Math.max(0, Math.min(1, v));

// stable per user+day jitter so the deck changes daily but not on every refresh
const jitter = (seed, id) => crypto.createHash('md5').update(`${seed}:${id}`).digest().readUInt16BE(0) / 65535;

const affinityParts = (p, profile, catalog) => {
  if (!profile) return { sim: 0, cat: 0, brand: 0, neg: 0 };
  const v = catalog.vectorOf(p.id);
  let sim = 0;
  if (profile.centroid && v && v.length === profile.centroid.length) for (let k = 0; k < v.length; k += 1) sim += v[k] * profile.centroid[k];
  return {
    sim: Math.max(0, sim),
    cat: profile.catAff.get(p.category_slug) || 0,
    brand: p.brand_name ? profile.brandAff.get(p.brand_name.toLowerCase()) || 0 : 0,
    neg: aversion(p, profile, catalog),
  };
};

const quickReasons = (p, catalog, extra = []) => [
  ...extra,
  p.discount_percent >= 10 ? `${Math.round(p.discount_percent)}% off right now` : null,
  p.sold_count >= catalog.bestsellerCut ? `Trending, ${p.sold_count} sold` : null,
  p.rating >= 4 && p.rating_count >= 3 ? `Rated ${stars(p.rating)} by ${plural(p.rating_count, 'shopper')}` : null,
].filter(Boolean).slice(0, 3);

// exclude: product ids swiped recently, in cart or bought. every 4th card explores a category the user rarely sees
const buildDeck = async ({ userId = null, exclude = new Set(), limit = 20 }) => {
  const catalog = await getCatalog();
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const personal = Boolean(profile && (profile.hasSignals || (profile.prefs.interests || []).length));
  const seed = `${userId || 'guest'}:${new Date().toISOString().slice(0, 10)}`;
  const gender = profile?.prefs?.gender && profile.prefs.gender !== 'any' ? profile.prefs.gender : null;
  const skip = new Set([...exclude, ...(profile ? [...profile.inCart, ...profile.purchased] : [])]);
  const pool = catalog.products
    .filter((p) => p.stock > 0 && !skip.has(p.id) && p.category_slug !== 'vehicle')
    .filter((p) => !(gender && p.gender === (gender === 'men' ? 'women' : 'men')));

  const scored = pool.map((p) => {
    const a = affinityParts(p, profile, catalog);
    const j = jitter(seed, p.id);
    const score = personal
      ? 0.28 * a.sim + 0.22 * a.cat + 0.06 * a.brand + 0.16 * p._quality + 0.12 * p._popularity + 0.06 * p._discount + 0.1 * j - 0.35 * a.neg
      : 0.4 * p._quality + 0.3 * p._popularity + 0.1 * p._discount + 0.2 * j;
    // everyday groceries make a dull swipe card unless the user actually shops them
    const dull = p.category_slug === 'groceries' && a.cat < 0.3 ? 0.6 : 1;
    return { p, score: score * dull, a, j };
  }).sort((x, y) => y.score - x.score);

  const top = new Set(profile?.topCategories || []);
  const exploreQueue = scored
    .filter((s) => !top.has(s.p.category_slug) && s.a.neg < 0.5)
    .sort((x, y) => (0.6 * y.p._quality + 0.4 * y.j) - (0.6 * x.p._quality + 0.4 * x.j));
  const used = new Set();
  const perCat = new Map();
  const cards = [];
  const take = (s, kind) => {
    used.add(s.p.id);
    perCat.set(s.p.category_slug, (perCat.get(s.p.category_slug) || 0) + 1);
    const extra = kind === 'explore'
      ? [`Something new: ${s.p.category_name}`]
      : personal && s.a.cat >= 0.5 ? [`Matches your taste for ${s.p.category_name}`] : personal && s.a.sim > 0.55 ? ['Similar to things you liked'] : [];
    cards.push({ product: s.p, score: +clamp01(s.score).toFixed(3), reasons: quickReasons(s.p, catalog, extra), kind });
  };
  // a category may hold at most ~25% of the deck so it never feels repetitive
  const cap = Math.max(2, Math.ceil(limit / 4));
  let ei = 0;
  for (const s of scored) {
    if (cards.length >= limit) break;
    if (personal && cards.length % 4 === 3) {
      while (ei < exploreQueue.length && (used.has(exploreQueue[ei].p.id) || (perCat.get(exploreQueue[ei].p.category_slug) || 0) >= cap)) ei += 1;
      if (ei < exploreQueue.length) take(exploreQueue[ei], 'explore');
      if (cards.length >= limit) break;
    }
    if (used.has(s.p.id) || (perCat.get(s.p.category_slug) || 0) >= cap) continue;
    take(s, personal ? 'personal' : 'popular');
  }
  return { cards, personalized: personal, strategy: personal ? 'taste + exploration' : 'popular + diverse' };
};

// swipes: [{ product_id, type: like|pass|cart, created_at }] (source = discover)
const tasteFrom = async ({ userId, swipes }) => {
  const catalog = await getCatalog();
  const W = { like: 1, cart: 1.5 };
  const pos = new Map();
  const negCount = new Map();
  const prices = [];
  const brands = new Map();
  let positives = 0;
  let passes = 0;
  let dealBags = 0;
  for (const s of swipes) {
    const p = catalog.byId.get(s.product_id);
    if (!p) continue;
    if (s.type === 'pass') {
      passes += 1;
      negCount.set(p.category_slug, (negCount.get(p.category_slug) || 0) + 1);
      continue;
    }
    const w = W[s.type] || 0;
    if (!w) continue;
    positives += 1;
    pos.set(p.category_slug, (pos.get(p.category_slug) || 0) + w);
    prices.push(p.price);
    if (p.brand_name) brands.set(p.brand_name, (brands.get(p.brand_name) || 0) + 1);
    if (s.type === 'cart' && p.discount_percent >= 10) dealBags += 1;
  }
  const nameOf = (slug) => catalog.taxonomy.find((t) => t.slug === slug)?.name || slug;
  let categories = [];
  const totalPos = [...pos.values()].reduce((a, b) => a + b, 0);
  if (totalPos) {
    categories = [...pos].sort((a, b) => b[1] - a[1]).slice(0, 5)
      .map(([slug, w]) => ({ slug, name: nameOf(slug), share: +(w / totalPos).toFixed(2) }));
  } else if (userId) {
    const profile = await getProfile(userId, catalog).catch(() => null);
    const aff = profile ? [...profile.catAff].sort((a, b) => b[1] - a[1]).slice(0, 3) : [];
    const sum = aff.reduce((a, [, w]) => a + w, 0);
    categories = aff.map(([slug, w]) => ({ slug, name: nameOf(slug), share: +(w / (sum || 1)).toFixed(2) }));
  }
  prices.sort((a, b) => a - b);
  const priceAppetite = prices.length
    ? { min: prices[0], max: prices[prices.length - 1], avg: Math.round(prices.reduce((a, b) => a + b, 0) / prices.length) }
    : null;
  const n = positives + 0.5 * passes;
  const consistency = categories[0]?.share || 0;
  const confidence = +clamp01((1 - Math.exp(-n / 8)) * (0.6 + 0.4 * consistency)).toFixed(2);
  const topSignals = [];
  if (categories[0] && totalPos) topSignals.push(`You liked ${plural(Math.round(pos.get(categories[0].slug)), 'item')} in ${categories[0].name}`);
  const favBrand = [...brands].sort((a, b) => b[1] - a[1])[0];
  if (favBrand && favBrand[1] >= 2) topSignals.push(`${favBrand[0]} keeps catching your eye`);
  if (prices.length >= 2) {
    const lo = prices[Math.floor(prices.length * 0.2)];
    const hi = prices[Math.min(prices.length - 1, Math.ceil(prices.length * 0.8) - 1)];
    topSignals.push(`Your sweet spot is ${money(lo)}${hi > lo ? ` to ${money(hi)}` : ''}`);
  }
  const skipped = [...negCount].filter(([slug, c]) => c >= 2 && !pos.has(slug)).sort((a, b) => b[1] - a[1])[0];
  if (skipped) topSignals.push(`You usually skip ${nameOf(skipped[0])}`);
  if (dealBags >= 2) topSignals.push('You bag the deals');
  return { categories, priceAppetite, confidence, topSignals: topSignals.slice(0, 4), swipes: { likes: positives, passes } };
};

const DEPT_HEADLINES = {
  electronics: 'Tech everyone is talking about',
  fashion: 'Fresh fits and finishing touches',
  'beauty-personal-care': 'Glow-up essentials',
  'home-living': 'Make your space feel new',
  groceries: 'Pantry favourites, delivered',
  'sports-outdoors': 'Gear up and get moving',
  automotive: 'Rides worth a closer look',
};

// one short story per department: 5-8 products ordered by trending + discount
const buildReels = async ({ userId = null, perDepartment = 6 }) => {
  const catalog = await getCatalog();
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const size = Math.max(5, Math.min(8, perDepartment));
  const depts = new Map();
  for (const t of catalog.taxonomy) if (!depts.has(t.departmentSlug)) depts.set(t.departmentSlug, { slug: t.departmentSlug, name: t.departmentName });
  const deptAff = new Map();
  if (profile) for (const [slug, w] of profile.catAff) {
    const d = catalog.taxonomy.find((t) => t.slug === slug)?.departmentSlug;
    if (d) deptAff.set(d, (deptAff.get(d) || 0) + w);
  }
  const reels = [];
  for (const d of depts.values()) {
    const items = catalog.products
      .filter((p) => p.department_slug === d.slug && p.stock > 0 && !profile?.passed?.has(p.id))
      .map((p) => ({ p, score: 0.5 * p._popularity + 0.3 * p._discount + 0.2 * p._quality }))
      .sort((a, b) => b.score - a.score);
    if (items.length < 5) continue;
    const picked = [];
    const perCat = new Map();
    const catCount = new Set(items.map((it) => it.p.category_slug)).size;
    const cap = Math.max(3, Math.ceil(size / catCount));
    for (const it of items) {
      const c = perCat.get(it.p.category_slug) || 0;
      if (c >= cap) continue;
      perCat.set(it.p.category_slug, c + 1);
      picked.push(it.p);
      if (picked.length >= size) break;
    }
    const maxOff = Math.max(...picked.map((p) => p.discount_percent || 0));
    const from = Math.min(...picked.map((p) => p.price));
    reels.push({
      id: d.slug,
      department: d,
      headline: maxOff >= 15 ? `${d.name}: up to ${Math.round(maxOff)}% off` : DEPT_HEADLINES[d.slug] || `Trending in ${d.name}`,
      subtitle: `${picked.length} picks shoppers love right now, from ${money(from)}`,
      coverImage: picked[0]?.thumbnail_url || null,
      products: picked,
      affinity: +(deptAff.get(d.slug) || 0).toFixed(3),
    });
  }
  if (profile) reels.sort((a, b) => b.affinity - a.affinity);
  return { reels, personalized: Boolean(profile && deptAff.size) };
};

const ZONES = [
  { id: 'desk', label: 'Study desk', tagline: 'Laptops, tablets and gadgets', department: 'electronics', categories: ['laptops', 'tablets', 'mobile-accessories', 'smartphones'] },
  { id: 'wardrobe', label: 'Wardrobe', tagline: 'Outfits, shoes and accessories', department: 'fashion', categories: { women: ['womens-dresses', 'tops', 'womens-shoes', 'womens-bags', 'sunglasses'], men: ['mens-shirts', 'mens-shoes', 'mens-watches', 'sunglasses'], any: ['womens-dresses', 'mens-shirts', 'womens-shoes', 'mens-shoes', 'sunglasses'] } },
  { id: 'vanity', label: 'Vanity', tagline: 'Make-up, skin care and scents', department: 'beauty-personal-care', categories: ['beauty', 'skin-care', 'fragrances', 'womens-jewellery'] },
  { id: 'kitchen', label: 'Kitchen', tagline: 'Cookware and fresh groceries', department: 'home-living', categories: ['kitchen-accessories', 'groceries'] },
  { id: 'shelf', label: 'Living-room shelf', tagline: 'Decor and furniture', department: 'home-living', categories: ['home-decoration', 'furniture'] },
  { id: 'corner', label: 'Fitness corner', tagline: 'Sports and workout gear', department: 'sports-outdoors', categories: ['sports-accessories'] },
  { id: 'garage', label: 'Garage', tagline: 'Bikes and cars', department: 'automotive', categories: ['motorcycle', 'vehicle'] },
];

const buildRoom = async ({ userId = null }) => {
  const catalog = await getCatalog();
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const personal = Boolean(profile && (profile.hasSignals || (profile.prefs.interests || []).length));
  const gender = profile?.prefs?.gender && profile.prefs.gender !== 'any' ? profile.prefs.gender : 'any';
  const deptName = (slug) => catalog.taxonomy.find((t) => t.departmentSlug === slug)?.departmentName || slug;
  const catName = (slug) => catalog.taxonomy.find((t) => t.slug === slug)?.name || slug;
  return ZONES.map((z) => {
    const cats = Array.isArray(z.categories) ? z.categories : z.categories[gender] || z.categories.any;
    const ranked = catalog.products
      .filter((p) => cats.includes(p.category_slug) && p.stock > 0 && !profile?.passed?.has(p.id))
      .map((p) => {
        const a = affinityParts(p, profile, catalog);
        const score = personal
          ? 0.3 * a.sim + 0.25 * a.cat + 0.05 * a.brand + 0.2 * p._quality + 0.1 * p._popularity + 0.1 * p._discount - 0.3 * a.neg
          : 0.5 * p._quality + 0.35 * p._popularity + 0.15 * p._discount;
        return { p, score };
      })
      .sort((x, y) => y.score - x.score);
    // three featured items from different categories where possible
    const featured = [];
    const seen = new Set();
    for (const r of ranked) {
      if (featured.length >= 3) break;
      if (seen.has(r.p.category_slug) && ranked.some((x) => !seen.has(x.p.category_slug) && !featured.includes(x.p))) continue;
      seen.add(r.p.category_slug);
      featured.push(r.p);
    }
    for (const r of ranked) {
      if (featured.length >= 3) break;
      if (!featured.includes(r.p)) featured.push(r.p);
    }
    return {
      id: z.id,
      label: z.label,
      tagline: z.tagline,
      department: { slug: z.department, name: deptName(z.department) },
      categories: cats.map((slug) => ({ slug, name: catName(slug) })),
      featured,
      personalized: personal,
    };
  });
};

module.exports = { buildDeck, tasteFrom, buildReels, buildRoom, ZONES };
