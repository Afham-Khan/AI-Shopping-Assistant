// shopping dna: interpretable taste traits from behaviour + a persona via nearest-prototype matching
const models = require('../models/ai.models');
const { getCatalog } = require('./retrieval/catalog');
const { TYPE_WEIGHTS } = require('./ranking/personalization');
const { money, list } = require('./format');

const clamp = (v) => Math.max(0, Math.min(1, Number.isFinite(v) ? v : 0));
const DEPT_KEYS = {
  electronics: 'electronics', fashion: 'fashion', 'beauty-personal-care': 'beauty', 'home-living': 'home',
  groceries: 'groceries', 'sports-outdoors': 'sports', automotive: 'automotive',
};

// persona prototypes: weighted trait/department mixes; the best-scoring prototype wins
const PERSONAS = [
  { title: 'The Tech Enthusiast', score: (t, d) => 1.6 * d.electronics + 0.3 * t.quality, description: 'You gravitate to gadgets and care about specs — so I lead with performance and highlight hardware details.' },
  { title: 'The Smart Saver', score: (t) => 1.0 * t.price + 0.8 * t.deal, description: 'You hunt for value and discounts — I surface deals, cheaper near-equivalents and coupon tips first.' },
  { title: 'The Brand Loyalist', score: (t, d, x) => (x.branded >= 4 ? 1.4 * t.brand : 0), description: 'You stick with brands you trust — your favourite brands get a boost in your recommendations.' },
  { title: 'The Trendsetter', score: (t, d) => 1.0 * t.trend + 0.6 * d.fashion, description: 'You like what is popular and new — trending and best-selling picks rank higher for you.' },
  { title: 'The Quality Connoisseur', score: (t) => 1.1 * t.quality + 0.6 * (1 - t.price), description: 'You pay for quality — I weigh ratings and reviews heavily and show premium options.' },
  { title: 'The Curious Explorer', score: (t) => 1.3 * t.breadth, description: 'You shop across many categories — I keep your feed diverse instead of repeating one category.' },
  { title: 'The Style Maven', score: (t, d) => 1.5 * d.fashion + 0.3 * d.beauty, description: 'Fashion is your thing — I focus on looks, colours and occasions when I suggest items.' },
  { title: 'The Beauty Buff', score: (t, d) => 1.6 * d.beauty, description: 'You love beauty and self-care — I pay attention to skin types, scents and review sentiment.' },
  { title: 'The Home Maker', score: (t, d) => 1.5 * (d.home + d.groceries), description: 'You shop for the home — kitchen, decor and essentials lead your recommendations.' },
  { title: 'The Careful Researcher', score: (t) => 1.2 * t.research, description: 'You compare a lot before buying — comparisons and review summaries are your best friends.' },
];

const percentileIn = (sorted, price) => {
  if (!sorted?.length) return 0.5;
  let lo = 0;
  while (lo < sorted.length && sorted[lo] < price) lo += 1;
  return sorted.length === 1 ? 0.5 : lo / (sorted.length - 1);
};

const shoppingDna = async (userId) => {
  const catalog = await getCatalog();
  const [signals, extras] = await Promise.all([models.userSignals(userId), models.profileExtras(userId)]);
  const { user, interactions, wishlist, cart, purchases } = signals;
  const prefs = user?.preferences || {};

  const events = [
    ...interactions.map((i) => ({ id: i.product_id, type: i.type })),
    ...wishlist.map((w) => ({ id: w.product_id, type: 'wishlist' })),
    ...cart.map((c) => ({ id: c.product_id, type: 'cart' })),
    ...purchases.map((p) => ({ id: p.product_id, type: 'purchase' })),
  ].filter((e) => catalog.byId.has(e.id));
  const counts = { views: 0, clicks: 0, wishlist: wishlist.length, cart: cart.length, purchases: purchases.length };
  for (const i of interactions) {
    if (i.type === 'view') counts.views += 1;
    if (i.type === 'click' || i.type === 'ai_click') counts.clicks += 1;
  }

  const pricesByCat = new Map();
  for (const p of catalog.products) {
    if (!pricesByCat.has(p.category_slug)) pricesByCat.set(p.category_slug, []);
    pricesByCat.get(p.category_slug).push(p.price);
  }
  for (const arr of pricesByCat.values()) arr.sort((a, b) => a - b);

  let W = 0;
  const acc = { pricePct: 0, discount: 0, quality: 0, highRated: 0, trend: 0 };
  const catW = new Map();
  const brandW = new Map();
  const deptW = new Map();
  const prices = [];
  const recentCut = Date.now() - 45 * 86400000;
  for (const e of events) {
    const p = catalog.byId.get(e.id);
    const w = TYPE_WEIGHTS[e.type] || 0.5;
    W += w;
    acc.pricePct += w * percentileIn(pricesByCat.get(p.category_slug), p.price);
    acc.discount += w * (p.discount_percent >= 12 ? 1 : 0);
    acc.quality += w * p._bayes;
    acc.highRated += w * (p.rating >= 4.3 ? 1 : 0);
    acc.trend += w * (p.sold_count >= catalog.bestsellerCut || new Date(p.created_at).getTime() > recentCut ? 1 : 0);
    catW.set(p.category_slug, (catW.get(p.category_slug) || 0) + w);
    if (p.brand_name) brandW.set(p.brand_name, (brandW.get(p.brand_name) || 0) + w);
    const dk = DEPT_KEYS[p.department_slug] || p.department_slug;
    deptW.set(dk, (deptW.get(dk) || 0) + w);
    prices.push(p.price);
  }

  const brandTotal = [...brandW.values()].reduce((a, b) => a + b, 0);
  let brandLoyalty = 0;
  if (brandW.size === 1 && brandTotal >= 3) brandLoyalty = 1;
  else if (brandW.size > 1) {
    const H = [...brandW.values()].reduce((s, v) => s - (v / brandTotal) * Math.log(v / brandTotal), 0);
    brandLoyalty = 1 - H / Math.log(brandW.size);
  }
  const chatBudgetTurns = extras.conversations.filter((c) => c.context?.slots?.budget || c.context?.slots?.sort === 'price_asc').length;
  const couponShare = extras.orders.count ? extras.orders.with_coupon / extras.orders.count : 0;
  const has = W > 0;
  const t = {
    price: has ? clamp(0.65 * (1 - acc.pricePct / W) + 0.2 * (acc.discount / W) + 0.15 * Math.min(1, chatBudgetTurns / 3)) : 0.5,
    brand: has ? clamp(brandLoyalty) : 0,
    deal: has ? clamp(0.7 * (acc.discount / W) + 0.3 * couponShare) : 0,
    quality: has ? clamp(0.6 * ((acc.quality / W - 3.4) / 1.2) + 0.4 * (acc.highRated / W)) : 0.5,
    trend: has ? clamp(acc.trend / W) : 0,
    breadth: clamp(catW.size / Math.min(10, catalog.taxonomy.length || 10)),
    research: clamp(Math.log1p(counts.views + extras.searches.length) / Math.log1p(8 * (counts.purchases + counts.cart + 1))),
  };
  const deptTotal = [...deptW.values()].reduce((a, b) => a + b, 0) || 1;
  const d = Object.fromEntries(['electronics', 'fashion', 'beauty', 'home', 'groceries', 'sports', 'automotive'].map((k) => [k, (deptW.get(k) || 0) / deptTotal]));

  let persona;
  if (!has) {
    const interests = (prefs.interests || []).map((s) => catalog.taxonomy.find((c) => c.slug === s)?.name).filter(Boolean);
    persona = {
      title: 'The Fresh Explorer',
      description: interests.length
        ? `You're just getting started — I'm using your onboarding interests (${list(interests)}) until I learn more from what you browse.`
        : "You're just getting started — browse, wishlist or chat with me and your Shopping DNA will take shape.",
    };
  } else {
    const ranked = PERSONAS.map((p) => ({ ...p, value: p.score(t, d, { branded: brandTotal }) })).sort((a, b) => b.value - a.value);
    persona = { title: ranked[0].title, description: ranked[0].description, runnerUp: ranked[1].title };
  }

  const pct = (v) => `${Math.round(v * 100)}%`;
  const traits = [
    { key: 'price', label: 'Price sensitivity', value: +t.price.toFixed(2), description: `You usually pick items in the ${t.price > 0.6 ? 'lower' : t.price < 0.4 ? 'upper' : 'middle'} part of each category's price range.` },
    { key: 'brand', label: 'Brand loyalty', value: +t.brand.toFixed(2), description: brandW.size ? `${pct(([...brandW.values()].sort((a, b) => b - a)[0] || 0) / (brandTotal || 1))} of your branded activity is ${[...brandW].sort((a, b) => b[1] - a[1])[0][0]}.` : 'Not enough branded activity yet.' },
    { key: 'deal', label: 'Deal hunter', value: +t.deal.toFixed(2), description: `${pct(has ? acc.discount / W : 0)} of what you engage with is discounted 12%+${extras.orders.count ? `, coupons on ${pct(couponShare)} of orders` : ''}.` },
    { key: 'quality', label: 'Quality seeker', value: +t.quality.toFixed(2), description: has ? `Items you engage with average ${(acc.quality / W).toFixed(1)}★ (Bayesian).` : 'No rating signal yet.' },
    { key: 'trend', label: 'Trend explorer', value: +t.trend.toFixed(2), description: `${pct(t.trend)} of your picks are bestsellers or new arrivals.` },
    { key: 'breadth', label: 'Category breadth', value: +t.breadth.toFixed(2), description: `You've explored ${catW.size} of ${catalog.taxonomy.length} categories.` },
    { key: 'research', label: 'Research depth', value: +t.research.toFixed(2), description: `${counts.views} product views and ${extras.searches.length} searches for ${counts.purchases} purchases.` },
  ];

  const share = (map) => [...map].sort((a, b) => b[1] - a[1]).slice(0, 5);
  const catTotal = [...catW.values()].reduce((a, b) => a + b, 0) || 1;
  prices.sort((a, b) => a - b);
  return {
    persona,
    traits,
    topCategories: share(catW).map(([slug, w]) => ({ slug, name: catalog.taxonomy.find((c) => c.slug === slug)?.name || slug, share: +(w / catTotal).toFixed(3) })),
    topBrands: share(brandW).map(([name, w]) => ({ name, share: +(w / (brandTotal || 1)).toFixed(3) })),
    priceBand: prices.length
      ? { min: prices[0], max: prices[prices.length - 1], avg: Math.round(prices.reduce((a, b) => a + b, 0) / prices.length), median: prices[Math.floor(prices.length / 2)] }
      : { min: prefs.budget?.min ?? null, max: prefs.budget?.max ?? null, avg: null, median: null },
    signals: { views: counts.views, clicks: counts.clicks, wishlist: counts.wishlist, cart: counts.cart, purchases: counts.purchases, searches: extras.searches.length, chats: extras.conversations.length },
    howWeUseIt: [
      `Recommendations blend a taste vector built from ${events.length} weighted signals (purchase ×3, cart/wishlist ×2, click ×1, view ×0.7, decaying over ~3 weeks).`,
      catW.size ? `Your top categories (${list(share(catW).slice(0, 2).map(([s]) => catalog.taxonomy.find((c) => c.slug === s)?.name || s))}) get an affinity boost.` : 'Onboarding interests act as a starting point.',
      prices.length ? `Typical price band ${money(prices[0])} – ${money(prices[prices.length - 1])} keeps suggestions realistic.` : 'Your saved budget preference keeps suggestions realistic.',
    ],
    lastUpdated: new Date().toISOString(),
  };
};

module.exports = { shoppingDna, PERSONAS };
