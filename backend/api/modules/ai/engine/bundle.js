// ai bundle builder: goal -> role template (keywords + semantic match) -> candidates per role ->
// multiple-choice knapsack (dynamic programming over a discretized budget) maximizing quality x relevance
const models = require('../models/ai.models');
const nlu = require('./nlu');
const { getCatalog } = require('./retrieval/catalog');
const embeddings = require('./retrieval/embeddings');
const { analyzeText } = require('./retrieval/bm25');
const { cosine } = require('./retrieval/vectorspace');
const { money, list, stars, truncate } = require('./format');

const BUCKETS = 500;
const CANDIDATES_PER_ROLE = 8;

// role: { role, categories | byGender, keywords, features, required, weight }
const TEMPLATES = {
  gaming_setup: {
    title: 'Gaming setup', triggers: ['gaming', 'gamer', 'game setup', 'esports', 'streaming'],
    description: 'gaming setup with a powerful laptop, headphones, speaker and comfortable chair',
    roles: [
      { role: 'Gaming laptop', categories: ['laptops'], features: ['gaming'], required: true, weight: 3 },
      { role: 'Headphones', categories: ['mobile-accessories'], keywords: ['headphones', 'earphones', 'earbuds', 'airpods'], required: true, weight: 1.5 },
      { role: 'Gaming chair', categories: ['furniture'], keywords: ['chair'], weight: 1.2 },
      { role: 'Speaker', categories: ['mobile-accessories'], keywords: ['speaker', 'echo', 'homepod'], weight: 0.8 },
    ],
  },
  home_office: {
    title: 'Home office setup', triggers: ['office', 'work from home', 'wfh', 'home office', 'workspace', 'desk setup', 'remote work'],
    description: 'home office workspace with laptop, desk, ergonomic chair, lamp and accessories for productivity',
    roles: [
      { role: 'Laptop', categories: ['laptops'], features: ['work'], required: true, weight: 3 },
      { role: 'Office chair', categories: ['furniture'], keywords: ['chair', 'executive', 'office'], required: true, weight: 1.6 },
      { role: 'Desk / table', categories: ['furniture'], keywords: ['table', 'desk'], weight: 1.2 },
      { role: 'Desk lamp', categories: ['home-decoration'], keywords: ['lamp', 'light'], weight: 0.7 },
      { role: 'Headphones', categories: ['mobile-accessories'], keywords: ['headphones', 'earphones', 'airpods', 'earbuds'], weight: 0.9 },
    ],
  },
  university_kit: {
    title: 'University starter kit', triggers: ['university', 'uni', 'college', 'student', 'school', 'campus', 'semester', 'studies'],
    description: 'university student starter kit with laptop or tablet, earphones, watch and essentials',
    roles: [
      { role: 'Laptop or tablet', categories: ['laptops', 'tablets'], required: true, weight: 3 },
      { role: 'Earphones', categories: ['mobile-accessories'], keywords: ['earphones', 'earbuds', 'airpods', 'wireless'], required: true, weight: 1.2 },
      { role: 'Watch', byGender: { men: ['mens-watches'], women: ['womens-watches'], any: ['mens-watches', 'womens-watches'] }, weight: 0.9 },
      { role: 'Power bank / charger', categories: ['mobile-accessories'], keywords: ['charger', 'battery', 'magsafe', 'power'], weight: 0.8 },
      { role: 'Coffee & snacks', categories: ['groceries'], keywords: ['coffee', 'juice', 'water', 'honey'], weight: 0.4 },
    ],
  },
  gym_starter: {
    title: 'Gym starter pack', triggers: ['gym', 'workout', 'fitness', 'exercise', 'training', 'bodybuilding'],
    description: 'gym and fitness starter pack with protein, running shoes, wireless earbuds, water and sports gear',
    roles: [
      { role: 'Protein', categories: ['groceries'], keywords: ['protein'], required: true, weight: 1.5 },
      { role: 'Training shoes', byGender: { men: ['mens-shoes'], women: ['womens-shoes'], any: ['mens-shoes', 'womens-shoes'] }, keywords: ['sneakers', 'sports', 'running', 'trainers'], required: true, weight: 1.5 },
      { role: 'Wireless earbuds', categories: ['mobile-accessories'], keywords: ['wireless', 'earphones', 'earbuds'], weight: 1 },
      { role: 'Hydration', categories: ['groceries'], keywords: ['water', 'juice'], weight: 0.5 },
      { role: 'Sports gear', categories: ['sports-accessories'], weight: 0.8 },
    ],
  },
  gift_set: {
    title: 'Gift set', triggers: ['gift set', 'gift box', 'hamper', 'eid gift', 'gift', 'present', 'surprise'],
    description: 'curated gift set with fragrance, jewellery or watch, accessories and beauty items',
    roles: [
      { role: 'Fragrance', categories: ['fragrances'], required: true, weight: 1.5 },
      { role: 'Jewellery / watch', byGender: { men: ['mens-watches'], women: ['womens-jewellery', 'womens-watches'], any: ['womens-jewellery', 'mens-watches'] }, required: true, weight: 1.4 },
      { role: 'Bag / accessory', byGender: { men: ['sunglasses'], women: ['womens-bags'], any: ['sunglasses'] }, weight: 1 },
      { role: 'Beauty treat', byGender: { men: ['skin-care'], women: ['beauty'], any: ['skin-care'] }, weight: 0.7 },
    ],
  },
  skincare_routine: {
    title: 'Skincare routine', triggers: ['skincare', 'skin care', 'routine', 'self care', 'pamper', 'glow', 'beauty routine', 'makeup kit'],
    description: 'daily skincare and beauty routine with cleanser, moisturizer, makeup and fragrance',
    roles: [
      { role: 'Cleanser', categories: ['skin-care'], keywords: ['soap', 'wash', 'cleanser'], required: true, weight: 1.3 },
      { role: 'Moisturizer', categories: ['skin-care'], keywords: ['lotion', 'moisture', 'butter', 'cream'], required: true, weight: 1.3 },
      { role: 'Makeup', categories: ['beauty'], weight: 1 },
      { role: 'Fragrance', categories: ['fragrances'], weight: 0.8 },
    ],
  },
  kitchen_starter: {
    title: 'Kitchen starter set', triggers: ['kitchen', 'cooking', 'new home', 'housewarming', 'first apartment', 'cook'],
    description: 'kitchen starter set with cookware, knife, utensils, an appliance and pantry basics',
    roles: [
      { role: 'Cookware', categories: ['kitchen-accessories'], keywords: ['pan', 'pot', 'cooking'], required: true, weight: 1.4 },
      { role: 'Knife', categories: ['kitchen-accessories'], keywords: ['knife', 'knives', 'cutting'], weight: 1 },
      { role: 'Utensils', categories: ['kitchen-accessories'], keywords: ['spoon', 'spatula', 'tongs', 'grater', 'sieve'], weight: 0.9 },
      { role: 'Appliance', categories: ['kitchen-accessories'], keywords: ['microwave', 'blender', 'oven', 'electric'], weight: 1.2 },
      { role: 'Pantry basics', categories: ['groceries'], keywords: ['rice', 'oil', 'honey'], weight: 0.6 },
    ],
  },
  travel_kit: {
    title: 'Travel kit', triggers: ['travel', 'trip', 'vacation', 'holiday', 'tour', 'journey', 'safar'],
    description: 'travel kit with sunglasses, power bank, earphones, a watch and a bag',
    roles: [
      { role: 'Sunglasses', categories: ['sunglasses'], required: true, weight: 1 },
      { role: 'Power bank', categories: ['mobile-accessories'], keywords: ['battery', 'magsafe', 'charger', 'power'], required: true, weight: 1.1 },
      { role: 'Earphones', categories: ['mobile-accessories'], keywords: ['earphones', 'earbuds', 'airpods', 'wireless'], weight: 1 },
      { role: 'Watch', byGender: { men: ['mens-watches'], women: ['womens-watches'], any: ['mens-watches', 'womens-watches'] }, weight: 0.8 },
      { role: 'Bag', categories: ['womens-bags'], weight: 0.6 },
    ],
  },
  photography_kit: {
    title: 'Photography & vlogging kit', triggers: ['photography', 'vlog', 'vlogging', 'content creator', 'youtube', 'selfie', 'camera'],
    description: 'content creator kit with a camera phone, monopod or selfie stick, selfie lamp and power bank',
    roles: [
      { role: 'Camera phone', categories: ['smartphones'], features: ['camera'], required: true, weight: 3 },
      { role: 'Monopod / stick', categories: ['mobile-accessories'], keywords: ['monopod', 'selfie', 'stick', 'pedestal'], required: true, weight: 1 },
      { role: 'Lighting', categories: ['mobile-accessories'], keywords: ['lamp', 'light'], weight: 0.8 },
      { role: 'Power bank', categories: ['mobile-accessories'], keywords: ['battery', 'magsafe', 'power'], weight: 0.7 },
    ],
  },
  party_outfit: {
    title: 'Party / wedding look', triggers: ['party', 'wedding', 'shaadi', 'outfit', 'look', 'dinner', 'mehndi', 'reception', 'date night'],
    description: 'complete outfit for a party or wedding with clothing, shoes, accessories and fragrance',
    roles: [
      { role: 'Outfit', byGender: { men: ['mens-shirts'], women: ['womens-dresses', 'tops'], any: ['womens-dresses', 'mens-shirts'] }, required: true, weight: 2 },
      { role: 'Shoes', byGender: { men: ['mens-shoes'], women: ['womens-shoes'], any: ['womens-shoes', 'mens-shoes'] }, required: true, weight: 1.4 },
      { role: 'Accessory', byGender: { men: ['mens-watches'], women: ['womens-jewellery'], any: ['womens-jewellery', 'mens-watches'] }, weight: 1.1 },
      { role: 'Bag / eyewear', byGender: { men: ['sunglasses'], women: ['womens-bags'], any: ['sunglasses'] }, weight: 0.8 },
      { role: 'Fragrance', categories: ['fragrances'], weight: 0.9 },
    ],
  },
  living_room: {
    title: 'Living room makeover', triggers: ['living room', 'lounge', 'makeover', 'decor', 'redecorate', 'drawing room', 'furnish'],
    description: 'living room makeover with sofa, table, decor and lighting',
    roles: [
      { role: 'Sofa', categories: ['furniture'], keywords: ['sofa', 'couch'], required: true, weight: 2 },
      { role: 'Table', categories: ['furniture'], keywords: ['table', 'bedside'], weight: 1 },
      { role: 'Lamp', categories: ['home-decoration'], keywords: ['lamp', 'light'], weight: 0.8 },
      { role: 'Decor piece', categories: ['home-decoration'], keywords: ['decoration', 'vase', 'plant', 'showpiece', 'wall'], weight: 0.8 },
    ],
  },
};

const templateVectors = new Map();

// keyword triggers + semantic similarity between the goal and each template description
const chooseTemplate = async (goal, entities) => {
  const text = ` ${String(goal).toLowerCase()} `;
  const goalTokens = new Set(analyzeText(goal));
  const goalVec = await embeddings.embedQuery(goal);
  const scored = [];
  for (const [key, t] of Object.entries(TEMPLATES)) {
    let score = 0;
    for (const trig of t.triggers) if (text.includes(` ${trig} `) || text.includes(` ${trig}s `)) score += trig.includes(' ') ? 2 : 1.5;
    const descTokens = analyzeText(t.description);
    score += 0.3 * descTokens.filter((w) => goalTokens.has(w)).length;
    if (goalVec) {
      if (!templateVectors.has(key)) templateVectors.set(key, await embeddings.embedQuery(t.description));
      score += 2 * Math.max(0, cosine(goalVec, templateVectors.get(key)) - 0.2);
    }
    if (key === 'gift_set' && (entities.recipient || entities.occasion === 'eid') && !score) score += 1;
    scored.push({ key, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored[0].score >= 0.8 ? scored[0].key : null;
};

// a template made on the fly from the categories the nlu found ("phone and earbuds under 100k")
const adHocTemplate = (entities, catalog) => {
  if (!entities.categories.length) return null;
  return {
    title: `${list(entities.categories.map((c) => catalog.taxonomy.find((t) => t.slug === c)?.name || c))} bundle`,
    roles: entities.categories.slice(0, 5).map((c, i) => ({
      role: catalog.taxonomy.find((t) => t.slug === c)?.name || c, categories: [c], required: true, weight: i === 0 ? 2 : 1,
    })),
  };
};

const roleCategories = (role, gender) => role.categories || role.byGender?.[gender || 'any'] || role.byGender?.any || [];

const roleCandidates = (role, catalog, gender, budget) => {
  const cats = roleCategories(role, gender);
  const kw = (role.keywords || []).map((k) => k.toLowerCase());
  const feats = role.features || [];
  const scored = catalog.products
    .filter((p) => cats.includes(p.category_slug) && p.stock > 0 && p.price <= budget)
    .filter((p) => !(gender && p.gender === (gender === 'men' ? 'women' : 'men')))
    .map((p) => {
      const title = p.title.toLowerCase();
      const kwHit = kw.length ? (kw.some((k) => title.includes(k)) ? 1 : kw.some((k) => p._text.includes(k)) ? 0.5 : 0) : 0.6;
      const featHit = feats.length ? feats.filter((f) => p._text.includes(f)).length / feats.length : 0.5;
      const relevance = 0.65 * kwHit + 0.35 * featHit;
      const utility = 0.45 * p._quality + 0.35 * relevance + 0.15 * p._popularity + 0.05 * p._discount;
      return { p, relevance, utility, titleHit: kwHit === 1 };
    })
    .filter((c) => !kw.length || c.relevance > 0.2);
  // when real title matches exist, description-only matches don't qualify
  const titled = scored.filter((c) => c.titleHit);
  const pool = kw.length && titled.some((c) => c.p.price <= budget * 0.6) ? titled : scored;
  return pool.sort((a, b) => b.utility - a.utility).slice(0, CANDIDATES_PER_ROLE);
};

// multiple-choice knapsack: pick at most one product per role (required roles exactly one),
// maximizing sum(weight * utility) with total price <= budget. dp over BUCKETS cost units.
const knapsack = (groups, budget) => {
  const unit = budget / BUCKETS;
  const NEG = -Infinity;
  let dp = new Array(BUCKETS + 1).fill(NEG);
  dp[0] = 0;
  const choice = [];
  for (const g of groups) {
    const next = new Array(BUCKETS + 1).fill(NEG);
    const pick = new Array(BUCKETS + 1).fill(-1);
    for (let b = 0; b <= BUCKETS; b += 1) {
      if (dp[b] === NEG) continue;
      if (!g.required && dp[b] > next[b]) {
        next[b] = dp[b];
        pick[b] = -1;
      }
      g.candidates.forEach((c, i) => {
        const cost = Math.max(1, Math.ceil(c.p.price / unit));
        const nb = b + cost;
        if (nb > BUCKETS) return;
        const v = dp[b] + g.weight * c.utility;
        if (v > next[nb]) {
          next[nb] = v;
          pick[nb] = i;
        }
      });
    }
    // remember predecessor bucket for reconstruction
    choice.push({ pick, prev: dp });
    dp = next;
  }
  let best = -1;
  for (let b = 0; b <= BUCKETS; b += 1) if (dp[b] !== NEG && (best === -1 || dp[b] > dp[best])) best = b;
  if (best === -1) return null;
  const selected = new Array(groups.length).fill(null);
  let b = best;
  for (let gi = groups.length - 1; gi >= 0; gi -= 1) {
    const i = choice[gi].pick[b];
    if (i >= 0) {
      selected[gi] = groups[gi].candidates[i];
      b -= Math.max(1, Math.ceil(groups[gi].candidates[i].p.price / unit));
    }
  }
  return { selected, value: dp[best] };
};

const cardReasons = (c, role, budget) => [
  `Best ${role.role.toLowerCase()} for this budget`,
  c.p.rating >= 4 && c.p.rating_count >= 3 ? `Rated ${stars(c.p.rating)} by ${c.p.rating_count} shoppers` : null,
  `${Math.round((c.p.price / budget) * 100)}% of your budget`,
  c.p.discount_percent >= 10 ? `${Math.round(c.p.discount_percent)}% off right now` : null,
].filter(Boolean);

const buildBundle = async ({ goal, budget, gender = null }) => {
  const catalog = await getCatalog();
  const a = nlu.analyze(goal);
  const e = a.entities;
  const total = Number(budget) || e.budget?.max || e.budget?.target || null;
  if (!total || total < 500) return { error: 'budget', message: 'Please give a total budget (at least Rs 500).' };
  const who = gender || e.gender || null;
  const key = await chooseTemplate(goal, e);
  const template = key ? TEMPLATES[key] : adHocTemplate(e, catalog);
  if (!template) return { error: 'goal', message: "I couldn't work out what the bundle is for. Try “gaming setup”, “home office”, “gym starter” or “skincare routine”." };

  const groups = template.roles.map((role) => {
    const candidates = roleCandidates(role, catalog, who, total);
    return { role, required: Boolean(role.required), weight: role.weight || 1, candidates };
  });
  // a product may only fill one role: keep it where it is most relevant
  const owner = new Map();
  groups.forEach((g, gi) => g.candidates.forEach((c) => {
    const cur = owner.get(c.p.id);
    if (!cur || c.relevance > cur.relevance) owner.set(c.p.id, { gi, relevance: c.relevance });
  }));
  groups.forEach((g, gi) => { g.candidates = g.candidates.filter((c) => owner.get(c.p.id).gi === gi); });
  // required roles with nothing affordable become optional (reported honestly)
  const unaffordable = groups.filter((g) => g.required && !g.candidates.length).map((g) => g.role.role);
  groups.forEach((g) => { if (!g.candidates.length) g.required = false; });
  let solution = knapsack(groups, total);
  const relaxedRequired = [];
  // infeasible: demote the least important required role first until a combination fits
  while (!solution && groups.some((g) => g.required)) {
    const weakest = groups.filter((g) => g.required).sort((a, b) => a.weight - b.weight)[0];
    weakest.required = false;
    relaxedRequired.push(weakest.role.role);
    solution = knapsack(groups, total);
  }
  const items = [];
  const skipped = [];
  groups.forEach((g, i) => {
    const c = solution?.selected[i];
    if (!c) {
      skipped.push(g.role.role);
      return;
    }
    const alternatives = g.candidates.filter((x) => x.p.id !== c.p.id).sort((x, y) => x.p.price - y.p.price).slice(0, 2);
    items.push({
      role: g.role.role,
      product: { product: c.p, score: +Math.min(1, c.utility).toFixed(3), reasons: cardReasons(c, g.role, total) },
      alternatives: alternatives.map((x) => x.p),
      required: Boolean(g.role.required),
    });
  });
  const spent = items.reduce((s, it) => s + it.product.product.price, 0);
  const biggest = items.slice().sort((x, y) => y.product.product.price - x.product.product.price)[0];

  const coupons = await models.activeCoupons().catch(() => []);
  const tips = [];
  for (const it of items) {
    const cheaper = it.alternatives.find((p) => p.price < it.product.product.price);
    if (cheaper) tips.push({ save: it.product.product.price - cheaper.price, text: `Swap the ${it.product.product.title} for ${cheaper.title} to save ${money(it.product.product.price - cheaper.price)}.` });
  }
  tips.sort((x, y) => y.save - x.save);
  const savingsTips = tips.slice(0, 2).map((t) => t.text);
  const optional = items.filter((it) => !it.required).sort((x, y) => y.product.product.price - x.product.product.price)[0];
  if (optional) savingsTips.push(`The ${optional.role.toLowerCase()} is optional — skipping it saves ${money(optional.product.product.price)}.`);
  const coupon = coupons.find((c) => spent >= Number(c.min_order_amount || 0));
  if (coupon) savingsTips.push(`Use code ${coupon.code} at checkout: ${coupon.description}.`);

  const explanation = [
    items.length
      ? `I split your ${money(total)} budget across ${items.length} pieces for a ${template.title.toLowerCase()}, choosing the combination with the best overall ratings and fit (a knapsack optimization over ${groups.reduce((s, g) => s + g.candidates.length, 0)} candidates).`
      : `I couldn't fit a ${template.title.toLowerCase()} into ${money(total)}.`,
    biggest ? `The ${biggest.role.toLowerCase()} is the biggest piece (${Math.round((biggest.product.product.price / total) * 100)}% of the budget).` : '',
    skipped.length ? `I left out ${list(skipped.map((s) => s.toLowerCase()))} to stay within budget.` : '',
    unaffordable.length ? `Nothing affordable for ${list(unaffordable.map((s) => s.toLowerCase()))} at this budget.` : '',
    relaxedRequired.length ? `Everything didn't fit in ${money(total)}, so I made the ${list(relaxedRequired.map((r) => r.toLowerCase()))} optional.` : '',
    `Total ${money(spent)}, leaving ${money(total - spent)}.`,
  ].filter(Boolean).join(' ');

  return {
    title: template.title + (who ? ` for ${who}` : ''),
    template: key || 'custom',
    goal: truncate(goal, 120),
    total: spent,
    budget: total,
    remaining: total - spent,
    items,
    skippedRoles: skipped,
    explanation,
    savingsTips,
  };
};

module.exports = { buildBundle, knapsack, chooseTemplate, TEMPLATES };
