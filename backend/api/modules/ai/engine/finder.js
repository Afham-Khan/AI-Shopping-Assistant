// guided product finder: per-department question flows -> slots -> hybrid retrieval
const { getCatalog } = require('./retrieval/catalog');
const { retrieve } = require('./retrieval/search');
const { getProfile } = require('./ranking/personalization');
const { describe, budgetPhrase } = require('./dialogue/nlg');
const { money, shortMoney, titleCase } = require('./format');

const opt = (label, value) => ({ label, value });

const FLOWS = {
  electronics: {
    title: 'Find your perfect gadget', icon: 'devices', categories: ['smartphones', 'laptops', 'tablets', 'mobile-accessories'],
    questions: [
      { id: 'type', title: 'What are you looking for?', type: 'single', options: [opt('Smartphone', 'smartphones'), opt('Laptop', 'laptops'), opt('Tablet', 'tablets'), opt('Accessories', 'mobile-accessories')] },
      { id: 'use', title: 'What will you mainly use it for?', type: 'multi', options: [opt('Gaming', 'gaming'), opt('Photography', 'camera'), opt('Long battery life', 'battery'), opt('Work & study', 'work'), opt('Movies & display', 'display'), opt('Portability', 'lightweight')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
      { id: 'brand', title: 'Any brand preference?', type: 'single', dynamic: 'brands' },
    ],
  },
  fashion: {
    title: 'Style finder', icon: 'checkroom', categories: ['mens-shirts', 'mens-shoes', 'mens-watches', 'tops', 'womens-dresses', 'womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses'],
    questions: [
      { id: 'for', title: 'Who is it for?', type: 'single', options: [opt('Men', 'men'), opt('Women', 'women')] },
      { id: 'category', title: 'What kind of item?', type: 'single', options: [opt('Clothing', 'clothing'), opt('Shoes', 'shoes'), opt('Watches', 'watches'), opt('Bags', 'bags'), opt('Jewellery', 'jewellery'), opt('Sunglasses', 'sunglasses')] },
      { id: 'occasion', title: "What's the occasion?", type: 'single', options: [opt('Casual', 'casual'), opt('Office', 'office'), opt('Wedding / party', 'wedding'), opt('Eid', 'eid'), opt('Sports', 'gym')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
      { id: 'color', title: 'Preferred colour?', type: 'single', options: [opt('Any', 'any'), opt('Black', 'black'), opt('White', 'white'), opt('Blue', 'blue'), opt('Red', 'red'), opt('Brown', 'brown'), opt('Gold', 'gold')] },
    ],
  },
  beauty: {
    title: 'Beauty matchmaker', icon: 'spa', categories: ['beauty', 'fragrances', 'skin-care'],
    questions: [
      { id: 'type', title: 'What are you shopping for?', type: 'single', options: [opt('Makeup', 'beauty'), opt('Fragrance', 'fragrances'), opt('Skin & body care', 'skin-care')] },
      { id: 'skin', title: "What's your skin type?", type: 'single', options: [opt('Oily', 'oil_control'), opt('Dry', 'hydrating'), opt('Sensitive', 'sensitive'), opt('Combination', 'none'), opt('Normal', 'none')] },
      { id: 'concern', title: 'What matters most?', type: 'multi', options: [opt('Long-lasting', 'long_lasting'), opt('Hydration', 'hydrating'), opt('Gentle & natural', 'sensitive'), opt('Luxury feel', 'luxury')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
    ],
  },
  home: {
    title: 'Home makeover helper', icon: 'chair', categories: ['furniture', 'home-decoration', 'kitchen-accessories'],
    questions: [
      { id: 'room', title: 'Which space are you shopping for?', type: 'single', options: [opt('Kitchen', 'kitchen-accessories'), opt('Living room', 'furniture'), opt('Bedroom', 'bedroom'), opt('Decor & accents', 'home-decoration')] },
      { id: 'style', title: 'Which style do you like?', type: 'single', options: [opt('Modern', 'modern'), opt('Classic', 'classic'), opt('Minimal', 'minimal'), opt('Cozy', 'cozy')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
    ],
  },
  sports: {
    title: 'Gear up', icon: 'sports_cricket', categories: ['sports-accessories'],
    questions: [
      { id: 'activity', title: 'Which sport or activity?', type: 'single', options: [opt('Cricket', 'cricket'), opt('Football', 'football'), opt('Tennis & badminton', 'tennis badminton'), opt('Basketball', 'basketball'), opt('Baseball', 'baseball'), opt('Golf', 'golf'), opt('Volleyball', 'volleyball')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
    ],
  },
  groceries: {
    title: 'Grocery run', icon: 'shopping_basket', categories: ['groceries'],
    questions: [
      { id: 'type', title: 'What do you need?', type: 'multi', options: [opt('Fruits', 'fruits'), opt('Vegetables', 'vegetables'), opt('Meat & seafood', 'meat seafood'), opt('Dairy & eggs', 'dairy'), opt('Beverages', 'beverages'), opt('Pantry essentials', 'essentials grains condiments')] },
      { id: 'preference', title: 'Any preference?', type: 'single', options: [opt('Fresh & organic', 'organic'), opt('Healthy', 'healthy'), opt('No preference', 'none')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
    ],
  },
  automotive: {
    title: 'Ride finder', icon: 'directions_car', categories: ['motorcycle', 'vehicle'],
    questions: [
      { id: 'type', title: 'Two wheels or four?', type: 'single', options: [opt('Motorcycle', 'motorcycle'), opt('Car', 'vehicle')] },
      { id: 'use', title: 'How will you use it?', type: 'single', options: [opt('Daily commute', 'commute city'), opt('Speed & sport', 'sport speed'), opt('Family trips', 'family suv minivan')] },
      { id: 'budget', title: "What's your budget?", type: 'budget' },
    ],
  },
};

const nice = (v) => {
  if (v <= 0) return 0;
  const mag = 10 ** Math.floor(Math.log10(v));
  return Math.round(v / (mag / 2)) * (mag / 2);
};

// budget brackets from the department's price quartiles so every option returns results
const budgetOptions = (prices) => {
  const s = prices.slice().sort((a, b) => a - b);
  if (!s.length) return [opt('Any budget', 'any')];
  const q = (f) => nice(s[Math.min(s.length - 1, Math.floor(s.length * f))]);
  const cuts = [...new Set([q(0.25), q(0.5), q(0.8)])].filter((c) => c > 0);
  const options = [opt(`Under ${shortMoney(cuts[0])}`, `0-${cuts[0]}`)];
  for (let i = 1; i < cuts.length; i += 1) options.push(opt(`${shortMoney(cuts[i - 1])} – ${shortMoney(cuts[i]).replace('Rs ', '')}`, `${cuts[i - 1]}-${cuts[i]}`));
  options.push(opt(`Above ${shortMoney(cuts[cuts.length - 1])}`, `${cuts[cuts.length - 1]}-`));
  options.push(opt('No limit', 'any'));
  return options;
};

const deptSlug = (catalog, key) => catalog.taxonomy.find((c) => FLOWS[key].categories.includes(c.slug))?.departmentSlug || key;

const getFlows = async () => {
  const catalog = await getCatalog();
  return Object.entries(FLOWS).map(([key, flow]) => {
    const products = catalog.products.filter((p) => flow.categories.includes(p.category_slug));
    const brandCounts = new Map();
    for (const p of products) if (p.brand_name) brandCounts.set(p.brand_name, (brandCounts.get(p.brand_name) || 0) + 1);
    const brands = [...brandCounts].sort((a, b) => b[1] - a[1]).slice(0, 7).map(([b]) => opt(b, b.toLowerCase()));
    return {
      department: catalog.taxonomy.find((c) => c.departmentSlug === deptSlug(catalog, key))?.departmentName || titleCase(key),
      slug: deptSlug(catalog, key),
      key,
      title: flow.title,
      icon: flow.icon,
      questions: flow.questions.map((q) => ({
        id: q.id,
        title: q.title,
        type: q.type,
        options: q.type === 'budget' ? budgetOptions(products.map((p) => p.price)) : q.dynamic === 'brands' ? [opt('No preference', 'any'), ...brands] : q.options,
      })),
    };
  });
};

const parseBudget = (value) => {
  if (!value || value === 'any') return null;
  if (typeof value === 'object') return { min: Number(value.min) || null, max: Number(value.max) || null };
  const [min, max] = String(value).split('-').map((v) => (v === '' ? null : Number(v)));
  return { min: min || null, max: Number.isFinite(max) && max ? max : null };
};

const asArray = (v) => (Array.isArray(v) ? v : v == null || v === '' ? [] : [v]);

const FASHION_CATS = {
  clothing: { men: ['mens-shirts'], women: ['tops', 'womens-dresses'] },
  shoes: { men: ['mens-shoes'], women: ['womens-shoes'] },
  watches: { men: ['mens-watches'], women: ['womens-watches'] },
  bags: { men: ['womens-bags'], women: ['womens-bags'] },
  jewellery: { men: ['womens-jewellery'], women: ['womens-jewellery'] },
  sunglasses: { men: ['sunglasses'], women: ['sunglasses'] },
};

// answers -> retrieval slots
const answersToSlots = (key, answers = {}) => {
  const flow = FLOWS[key];
  const s = { categories: [], brands: [], features: [], keywords: [], excludeBrands: [], excludeColors: [], budget: parseBudget(answers.budget) };
  const feats = (v) => asArray(v).filter((x) => x && x !== 'none');
  if (key === 'electronics') {
    s.categories = asArray(answers.type).length ? asArray(answers.type) : flow.categories;
    s.features = feats(answers.use);
    if (answers.brand && answers.brand !== 'any') s.brands = [String(answers.brand).toLowerCase()];
  } else if (key === 'fashion') {
    s.gender = answers.for === 'men' || answers.for === 'women' ? answers.for : null;
    const map = FASHION_CATS[answers.category];
    s.categories = map ? map[s.gender || 'women'].concat(s.gender ? [] : map.men) : flow.categories;
    s.categories = [...new Set(s.categories)];
    if (answers.occasion) s.occasion = answers.occasion;
    if (answers.color && answers.color !== 'any') s.color = answers.color;
  } else if (key === 'beauty') {
    s.categories = asArray(answers.type).length ? asArray(answers.type) : flow.categories;
    s.features = [...new Set([...feats(answers.skin), ...feats(answers.concern)])];
  } else if (key === 'home') {
    const room = answers.room;
    s.categories = room === 'bedroom' ? ['furniture'] : room ? [room] : flow.categories;
    if (room === 'bedroom') s.keywords.push('bed', 'bedside');
    if (answers.style === 'cozy') s.features.push('comfort');
    else if (answers.style) s.keywords.push(answers.style);
  } else if (key === 'sports') {
    s.categories = flow.categories;
    if (answers.activity) s.keywords.push(...String(answers.activity).split(' '));
  } else if (key === 'groceries') {
    s.categories = flow.categories;
    for (const t of asArray(answers.type)) s.keywords.push(...String(t).split(' '));
    if (answers.preference && answers.preference !== 'none') s.features.push(answers.preference === 'healthy' ? 'organic' : answers.preference);
  } else if (key === 'automotive') {
    s.categories = asArray(answers.type).length ? asArray(answers.type) : flow.categories;
    if (answers.use) s.keywords.push(...String(answers.use).split(' '));
  }
  s.category = s.categories[0] || null;
  return s;
};

const resolveKey = (catalog, department) => {
  const d = String(department || '').toLowerCase();
  if (FLOWS[d]) return d;
  return Object.keys(FLOWS).find((k) => deptSlug(catalog, k) === d) || null;
};

const runFinder = async ({ department, answers, userId }) => {
  const catalog = await getCatalog();
  const key = resolveKey(catalog, department);
  if (!key) return null;
  const slots = answersToSlots(key, answers);
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const result = await retrieve(slots, { profile, limit: 8, perCategoryCap: slots.categories.length > 1 ? 3 : null });
  const top = result.items[0];
  const what = describe({ ...slots, keywords: key === 'sports' || key === 'groceries' ? slots.keywords : [] }, catalog);
  const summary = [
    result.relaxed.map((r) => r.message).join(' '),
    `Based on your answers, here are ${result.items.length} ${what}${slots.budget ? ` ${budgetPhrase(slots.budget)}` : ''}.`,
    top ? `Best match: **${top.product.title}** at **${money(top.product.price)}**${top.reasons[0] ? ` — ${top.reasons[0].charAt(0).toLowerCase()}${top.reasons[0].slice(1)}` : ''}.` : '',
  ].filter(Boolean).join(' ');
  return { summary, products: result.items, total: result.total, fallback: result.fallback, slots };
};

module.exports = { getFlows, runFinder, answersToSlots, budgetOptions, FLOWS };
