// Quality audit of the Zelora AI features other than core chat search ranking: compare, bundle, gift finder,
// complete the look, spec explainer, product Q&A, review summary, similar / bought together, cart insights,
// shopping DNA, guided finder, smart search wrapper and Snap & Find.
//
//   npm run ai:audit                          -> runs everything, prints a scorecard, writes test/AI_FEATURE_AUDIT.md
//   npm run ai:audit -- --baseline            -> also saves this run as the BEFORE snapshot (test/fixtures/ai-feature-audit-baseline.json)
//   npm run ai:audit -- --only compare,qa     -> runs only some features (the report is not rewritten)
//   npm run ai:audit -- --verbose             -> prints every case, not just the failing ones
//   npm run ai:audit -- --no-visual           -> skips Snap & Find (it loads the CLIP model, ~300 MB)
//   npm run ai:audit -- --no-write            -> prints the scorecard without touching the report
//
// Everything runs in-process against the local database (read-only: carts and shopper histories used by the
// cart-insights and shopping-DNA cases are stubbed in memory, nothing is written). The checks are the things a
// shopper would notice ("a gift for dad is not a women's handbag", "8 GB RAM is not called flagship"), written
// independently of the engine's own scoring so a fix has to make the output genuinely better to pass.
process.env.LLM_PROVIDER = 'none';
require('dotenv').config({ quiet: true });
const fs = require('fs');
const path = require('path');
const db = require('../api/db/connection');
const models = require('../api/modules/ai/models/ai.models');
const engine = require('../api/modules/ai/engine');
const embeddings = require('../api/modules/ai/engine/retrieval/embeddings');
const { getCatalog } = require('../api/modules/ai/engine/retrieval/catalog');
const { buildBundle } = require('../api/modules/ai/engine/bundle');
const { buildGift } = require('../api/modules/ai/engine/gift');
const { completeLook, parseColor, colorHarmony } = require('../api/modules/ai/engine/outfit');
const { explainProduct } = require('../api/modules/ai/engine/explain');
const qa = require('../api/modules/ai/engine/qa');
const { reviewSummary } = require('../api/modules/ai/engine/reviews/summary');
const { detectAspects, aspectsFor, LABELS } = require('../api/modules/ai/engine/reviews/aspects');
const recommender = require('../api/modules/ai/engine/ranking/recommender');
const { cartInsights } = require('../api/modules/ai/engine/cartInsights');
const { shoppingDna } = require('../api/modules/ai/engine/shoppingDna');
const { TYPE_WEIGHTS } = require('../api/modules/ai/engine/ranking/personalization');
const finder = require('../api/modules/ai/engine/finder');
const { money } = require('../api/modules/ai/engine/format');
const { FREE_SHIPPING_THRESHOLD } = require('../helpers/constants');

const ROOT = path.join(__dirname, '..');
const BASELINE = path.join(ROOT, 'test/fixtures/ai-feature-audit-baseline.json');
const REPORT = path.join(ROOT, 'test/AI_FEATURE_AUDIT.md');
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const only = (() => {
  const i = argv.indexOf('--only');
  return i >= 0 && argv[i + 1] ? new Set(argv[i + 1].split(',')) : null;
})();

let catalog;
const P = (id) => catalog.byId.get(Number(id));
const results = [];
const record = (feature, name, failures) => results.push({ feature, name, pass: !failures.length, failures });

// ------------------------------------------------------------------------------------------------ shared helpers

const OPPOSITE = { men: 'women', women: 'men' };
const genderOf = (p) => {
  if (p.gender === 'men' || p.gender === 'women') return p.gender;
  if (/^womens-|^tops$/.test(p.category_slug)) return 'women';
  if (/^mens-/.test(p.category_slug)) return 'men';
  return 'unisex';
};
const wrongGender = (p, gender) => Boolean(gender && OPPOSITE[gender] && genderOf(p) === OPPOSITE[gender]);
const isKidsItem = (p) => /\b(?:girls?|boys?|kids?|children|toddlers?)\b|\bages? \d/i.test(`${p.title} ${p.specs?.['Ideal For'] || ''}`);
const levelOf = (p, key) => explainProduct(p).specs.find((s) => s.key.toLowerCase() === key.toLowerCase())?.level || 0;
const r1 = (x) => Math.round(Number(x) * 10) / 10;
const discreteGpu = (p) => /rtx|gtx|radeon rx/i.test(String(p.specs?.Graphics || ''));
// first number + unit in a spec value: the headline figure a shopper reads ("64 GB (microSD up to 256 GB)" -> 64 GB)
const headline = (v) => {
  const m = String(v || '').toLowerCase().match(/(\d+(?:\.\d+)?)\s*(tb|gb|mah|mp|hz|w|hours?|h)\b/);
  if (!m) return null;
  const unit = m[2] === 'tb' ? 'gb' : m[2].replace(/^hours?$/, 'h');
  return { unit, value: Number(m[1]) * (m[2] === 'tb' ? 1024 : 1) };
};
const subtypes = (p) => new Set((p.tags || []).map((t) => t.toLowerCase())
  .filter((t) => t !== p.category_slug && !['electronics', 'fashion', 'beauty', 'groceries', 'furniture', 'watches', 'fashion accessories', 'personal care', 'clothing', 'footwear', 'eyewear'].includes(t) && t !== String(p.brand_name || '').toLowerCase()));
const sameSubtype = (a, b) => [...subtypes(a)].some((t) => subtypes(b).has(t));

const title = (re) => (p) => re.test(p.title);
const cat = (...slugs) => (p) => slugs.includes(p.category_slug);
const both = (a, b) => (p) => a(p) && b(p);
const AUDIO = both(cat('mobile-accessories'), title(/airpods|earphones|earbuds|headphones|beats|buds/i));
const NOVELTY = (p) => /costume|novelty/i.test(`${p.specs?.Use || ''} ${p.specs?.Style || ''}`);

// categories a shopper would accept as "goes with" / "bought together" for a base category
const COMPLEMENT_OK = {
  smartphones: ['mobile-accessories'],
  tablets: ['mobile-accessories'],
  laptops: ['mobile-accessories'],
  // a phone is not "the rest of the set" for earbuds: accessories pair with accessories
  'mobile-accessories': ['mobile-accessories'],
  'mens-shirts': ['mens-shoes', 'mens-watches', 'sunglasses', 'fragrances'],
  'mens-shoes': ['mens-shirts', 'mens-watches', 'sunglasses', 'sports-accessories'],
  'mens-watches': ['mens-shirts', 'mens-shoes', 'sunglasses', 'fragrances'],
  tops: ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses', 'fragrances', 'beauty'],
  'womens-dresses': ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses', 'fragrances', 'beauty'],
  'womens-shoes': ['womens-dresses', 'tops', 'womens-bags', 'womens-jewellery'],
  'womens-bags': ['womens-jewellery', 'womens-watches', 'sunglasses', 'womens-shoes', 'womens-dresses', 'tops', 'beauty', 'fragrances'],
  'womens-jewellery': ['womens-dresses', 'tops', 'womens-bags', 'fragrances', 'womens-watches', 'beauty'],
  'womens-watches': ['womens-jewellery', 'womens-bags', 'womens-dresses', 'tops'],
  sunglasses: ['mens-watches', 'womens-bags', 'mens-shirts', 'tops', 'womens-dresses', 'mens-shoes', 'womens-shoes'],
  beauty: ['skin-care', 'fragrances', 'beauty'],
  fragrances: ['beauty', 'skin-care'],
  'skin-care': ['beauty', 'fragrances', 'skin-care'],
  furniture: ['home-decoration', 'furniture'],
  'home-decoration': ['furniture', 'home-decoration'],
  'kitchen-accessories': ['kitchen-accessories', 'groceries'],
  groceries: ['groceries', 'kitchen-accessories'],
  'sports-accessories': ['sports-accessories', 'mens-shoes', 'groceries'],
  motorcycle: ['sunglasses', 'mobile-accessories'],
  vehicle: ['mobile-accessories', 'sunglasses'],
};
const SPORT = /cricket|basketball|baseball|golf|tennis|football|volleyball|badminton|shuttlecock/i;
const sportOf = (p) => (`${p.title} ${(p.tags || []).join(' ')}`.match(SPORT)?.[0] || '').toLowerCase().replace('shuttlecock', 'badminton');
const DEVICES = new Set(['smartphones', 'tablets', 'laptops']);
const appleOnly = (p) => /iphone|ipad|\bmac\b|apple/i.test(String(p.specs?.Compatibility || '')) && !/android|windows/i.test(String(p.specs?.Compatibility || ''));
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
// an accessory that cannot work with the device (an iPhone 12 case for an iPhone 13 Pro, a MagSafe pack for a Samsung)
const incompatible = (device, acc) => {
  if (!DEVICES.has(device.category_slug) || acc.category_slug !== 'mobile-accessories') return false;
  // bluetooth audio works with anything; cases, MagSafe packs, Apple Watch and HomePod need the listed devices
  if (appleOnly(acc) && !AUDIO(acc) && device.brand_name !== 'Apple') return true;
  if (/\bcase\b|cover/i.test(acc.title) && device.category_slug === 'smartphones') return !norm(acc.specs?.Compatibility).includes(norm(device.title));
  return false;
};
const STUDIO = /pedestal|studio/i;
const complementOk = (base, p) => {
  if (incompatible(base, p) || (DEVICES.has(p.category_slug) && base.category_slug === 'mobile-accessories' && incompatible(p, base))) return false;
  if (base.category_slug === 'laptops' && p.category_slug === 'mobile-accessories') return AUDIO(p) || /speaker|echo|homepod/i.test(p.title);
  if (DEVICES.has(base.category_slug) && STUDIO.test(p.title)) return false;
  const catOk = base.category_slug === 'sports-accessories' && p.category_slug === 'sports-accessories'
    ? Boolean(sportOf(base)) && sportOf(base) === sportOf(p)
    : (COMPLEMENT_OK[base.category_slug] || []).includes(p.category_slug);
  // same sport is fine (a ball and a rim), the same item again is not ("Baseball Bat" / "Metal Baseball Bat")
  const lastWord = (x) => x.title.split(' ').pop().toLowerCase();
  if (base.category_slug === 'sports-accessories' && p.category_slug === 'sports-accessories') return catOk && lastWord(base) !== lastWord(p);
  return catOk && !(p.category_slug === base.category_slug && (sameSubtype(base, p) || DEVICES.has(p.category_slug)))
    && !(isKidsItem(p) && !isKidsItem(base));
};

// ------------------------------------------------------------------------------------------------ compare

const COMPARE_CASES = [
  { ids: [123, 130, 133] }, { ids: [125, 128] }, { ids: [126, 130, 136] }, { ids: [121, 122] }, { ids: [78, 79, 80] },
  { ids: [81, 82] }, { ids: [100, 107, 101] }, { ids: [159, 160, 161] }, { ids: [93, 94, 97] }, { ids: [6, 7, 8] },
  { ids: [88, 90, 91] }, { ids: [51, 61] }, { ids: [131, 132, 133] }, { ids: [128, 131, 135] },
  { ids: [123, 130, 133], need: 'for gaming', word: /gaming/i, specs: ['Processor', 'RAM'] },
  { ids: [125, 128, 134], need: 'for my mom', word: /mom/i, notDominated: true },
  { ids: [78, 79, 80], need: 'for gaming', word: /gaming/i, specs: ['Graphics'] },
  { ids: [78, 80, 82], need: 'for travel', word: /travel/i, specs: ['Weight', 'Battery Life'] },
  { ids: [126, 130, 133], need: 'for photography', word: /photo/i, specs: ['Rear Camera'] },
  { ids: [125, 129, 131], need: 'long battery life', word: /battery/i, specs: ['Battery'] },
];

const dominatedBy = (p, group) => group.find((q) => q.id !== p.id && q.price <= p.price && q.rating >= p.rating && (q.price < p.price || q.rating > p.rating) && q.rating_count >= 3);

const proConTopics = (lines, p) => {
  const ex = explainProduct(p).specs;
  const topics = new Set();
  for (const s of lines) {
    if (/\brat(?:ed|ing)\b/i.test(s) && !/^Reviewers|^Some reviewers/.test(s)) topics.add('rating');
    if (/cheapest|most expensive/i.test(s)) topics.add('price');
    let m = s.match(/^(?:Best|Basic|Fair) (.+?) \(/);
    if (m) topics.add(m[1].toLowerCase());
    const spec = ex.find((e) => s.startsWith(`${e.title}:`));
    if (spec) topics.add(spec.key.toLowerCase());
    m = s.match(/^(?:Reviewers praise|Some reviewers complain about) the (.+)$/);
    if (m) topics.add(`review:${m[1]}`);
  }
  return topics;
};

const auditCompare = async () => {
  for (const c of COMPARE_CASES) {
    const f = [];
    const name = `${c.ids.map((id) => P(id).title).join(' vs ')}${c.need ? ` — "${c.need}"` : ''}`;
    const r = await engine.compare(c.ids, { need: c.need || null });
    const group = r.products.map((x) => P(x.id));
    const n = group.length;
    if (r.rows.some((row) => row.values.length !== n || (row.bestIndex !== null && (row.bestIndex < 0 || row.bestIndex >= n)))) f.push('rows are not aligned with the products');
    const pick = (label) => P(r.verdict.picks.find((x) => x.label === label)?.productId);
    const best = pick('Best value');
    const dom = best && dominatedBy(best, group);
    if (dom) f.push(`"Best value" is ${best.title} (${money(best.price)}, ${best.rating}★) but ${dom.title} is cheaper or equal and rated higher (${money(dom.price)}, ${dom.rating}★)`);
    const bestReason = r.verdict.picks.find((x) => x.label === 'Best value')?.reason || '';
    const pct = bestReason.match(/(\d+)% cheaper than (.+)$/);
    if (pct) {
      const other = group.find((g) => g.title === pct[2]);
      if (other && Math.abs(Math.round((1 - best.price / other.price) * 100) - Number(pct[1])) > 1) f.push(`"Best value" reason says ${pct[1]}% cheaper, the real figure is ${Math.round((1 - best.price / other.price) * 100)}%`);
    }
    const top = pick('Top rated');
    const enough = group.filter((g) => g.rating_count >= 3);
    const maxRating = Math.max(...enough.map((g) => r1(g.rating)));
    const topReason = r.verdict.picks.find((x) => x.label === 'Top rated')?.reason || '';
    if (top && r1(top.rating) < maxRating && /highest rating/i.test(topReason)) {
      const higher = enough.find((g) => r1(g.rating) === maxRating);
      f.push(`"Top rated" says ${top.title} (${top.rating}★, ${top.rating_count} reviews) has the highest rating, but ${higher.title} has ${higher.rating}★ from ${higher.rating_count} reviews`);
    }
    for (const pc of r.prosCons) {
      const p = P(pc.productId);
      const clash = [...proConTopics(pc.pros, p)].filter((t) => proConTopics(pc.cons, p).has(t) && !t.startsWith('review:'));
      if (clash.length) f.push(`${p.title}: "${clash[0]}" is listed as both a pro and a con (${pc.pros.find((x) => proConTopics([x], p).has(clash[0]))} / ${pc.cons.find((x) => proConTopics([x], p).has(clash[0]))})`);
    }
    for (const row of r.rows) {
      if (!/^(storage|ram|battery|rear camera|front camera)$/i.test(row.label) || row.bestIndex === null) continue;
      const heads = row.values.map(headline);
      const units = new Set(heads.filter(Boolean).map((h) => h.unit));
      if (units.size !== 1) continue;
      const maxHead = Math.max(...heads.map((h) => h?.value ?? -Infinity));
      if ((heads[row.bestIndex]?.value ?? -Infinity) < maxHead) {
        const real = heads.findIndex((h) => h?.value === maxHead);
        f.push(`${row.label} row marks ${group[row.bestIndex].title} ("${row.values[row.bestIndex]}") as best over ${group[real].title} ("${row.values[real]}")`);
      }
    }
    if (c.need) {
      if (!r.forYou) f.push('no forYou pick for the need');
      else {
        const fy = P(r.forYou.productId);
        if (!c.word.test(r.forYou.reason)) f.push(`forYou reason does not mention the need: "${r.forYou.reason}"`);
        if (c.specs) {
          const score = (p) => c.specs.reduce((s, k) => s + levelOf(p, k), 0);
          const bestScore = Math.max(...group.map(score));
          if (score(fy) < bestScore) {
            const better = group.find((g) => score(g) === bestScore);
            f.push(`for "${c.need}" it picks ${fy.title} (${c.specs.map((k) => `${k} L${levelOf(fy, k)}`).join(', ')}) over ${better.title} (${c.specs.map((k) => `${k} L${levelOf(better, k)}`).join(', ')})`);
          }
        }
        if (c.notDominated) {
          const d = dominatedBy(fy, group);
          if (d) f.push(`for "${c.need}" it picks ${fy.title} although ${d.title} is cheaper and rated higher`);
        }
      }
    }
    record('compare', name, f);
  }
};

// ------------------------------------------------------------------------------------------------ bundle

const ROLE_FIT = {
  'Gaming laptop': cat('laptops'), Laptop: cat('laptops'), 'Laptop or tablet': cat('laptops', 'tablets'),
  Headphones: AUDIO, Earphones: AUDIO, 'Wireless earbuds': both(AUDIO, (p) => /wireless|airpods|buds/i.test(p.title) && !/max/i.test(p.title)),
  'Gaming chair': title(/chair/i), 'Office chair': title(/chair/i),
  Speaker: title(/echo|homepod|speaker/i), 'Desk / table': title(/\bdesk\b|writing table|work table|study table|dining table|coffee table/i),
  'Desk lamp': title(/lamp/i), Lamp: title(/lamp/i), Lighting: title(/lamp|light/i),
  Watch: cat('mens-watches', 'womens-watches'), 'Power bank / charger': both(cat('mobile-accessories'), title(/charger|power ?bank|battery pack/i)),
  'Power bank': both(cat('mobile-accessories'), title(/power ?bank|battery pack/i)),
  'Coffee & snacks': both(cat('groceries'), title(/coffee|juice|water|honey|snack|tea|chocolate/i)),
  Protein: title(/protein/i), 'Training shoes': both(cat('mens-shoes', 'womens-shoes'), (p) => /sneaker|trainer|running|sports/i.test(p.title) && !/cleats/i.test(p.title)),
  Hydration: title(/water|juice/i), 'Sports gear': cat('sports-accessories'),
  Fragrance: cat('fragrances'), 'Jewellery / watch': cat('womens-jewellery', 'mens-watches', 'womens-watches'),
  'Bag / accessory': cat('womens-bags', 'sunglasses'), 'Beauty treat': cat('beauty', 'skin-care'),
  Cleanser: both(cat('skin-care'), title(/soap|wash|cleanser/i)), Moisturizer: both(cat('skin-care'), (p) => /lotion|moisturi[sz]er|cream/i.test(p.title) && !/wash|soap/i.test(p.title)),
  Makeup: cat('beauty'), Cookware: both(cat('kitchen-accessories'), title(/\bpan\b|\bpot\b|\bwok\b/i)), Knife: title(/knife/i),
  Utensils: both(cat('kitchen-accessories'), title(/spoon|spatula|tongs|grater|sieve|whisk|turner|peeler|fork|rolling pin/i)),
  Appliance: both(cat('kitchen-accessories'), title(/microwave|blender|oven|stove/i)), 'Pantry basics': both(cat('groceries'), title(/rice|oil|honey|flour|sugar|salt|spice/i)),
  Sunglasses: cat('sunglasses'), Bag: cat('womens-bags'), 'Camera phone': cat('smartphones'),
  'Monopod / stick': title(/monopod|selfie stick/i), Outfit: cat('womens-dresses', 'tops', 'mens-shirts'), Shoes: cat('mens-shoes', 'womens-shoes'),
  Accessory: cat('womens-jewellery', 'mens-watches', 'womens-watches'), 'Bag / eyewear': cat('womens-bags', 'sunglasses'),
  Sofa: title(/sofa|couch/i), Table: title(/table/i), 'Decor piece': both(cat('home-decoration'), (p) => !/lamp/i.test(p.title)),
};

const BUNDLE_CASES = [
  { goal: 'gaming setup', budget: 400000 }, { goal: 'gaming setup', budget: 800000 }, { goal: 'home office setup', budget: 600000 },
  { goal: 'university starter kit', budget: 250000 }, { goal: 'gym starter pack', budget: 60000 }, { goal: 'gift set for her', budget: 60000, gender: 'women' },
  { goal: 'skincare routine', budget: 15000 }, { goal: 'kitchen starter set', budget: 40000 }, { goal: 'travel kit', budget: 120000 },
  { goal: 'vlogging kit', budget: 200000 }, { goal: 'party outfit for women', budget: 80000, gender: 'women', occasionWords: /party|parties|wedding|evening|formal|gala|festive|special occasions/i },
  { goal: 'wedding look for men', budget: 120000, gender: 'men', occasionWords: /party|parties|wedding|evening|formal|gala|festive|semi-formal|office/i }, { goal: 'living room makeover', budget: 900000 },
  { goal: 'gym starter pack for men', budget: 50000, gender: 'men' },
];

const auditBundle = async () => {
  for (const c of BUNDLE_CASES) {
    const f = [];
    const b = await buildBundle({ goal: c.goal, budget: c.budget });
    const name = `"${c.goal}" for ${money(c.budget)}`;
    if (b.error) {
      record('bundle', name, [`error: ${b.message}`]);
      continue;
    }
    const items = b.items.map((it) => ({ role: it.role, p: it.product.product }));
    const sum = items.reduce((s, it) => s + it.p.price, 0);
    if (sum > c.budget) f.push(`total ${money(sum)} is over the ${money(c.budget)} budget`);
    if (sum !== b.total || b.remaining !== c.budget - sum) f.push('total/remaining do not add up');
    const ids = items.map((it) => it.p.id);
    if (new Set(ids).size !== ids.length) f.push('the same product fills two roles');
    const used = new Set(ids);
    for (const it of items) {
      const fit = ROLE_FIT[it.role];
      if (fit && !fit(it.p)) f.push(`${it.role} is filled by "${it.p.title}" (${it.p.category_slug}), which is not a ${it.role.toLowerCase()}`);
      if (wrongGender(it.p, c.gender)) f.push(`${it.role}: "${it.p.title}" is for ${genderOf(it.p)} in a bundle for ${c.gender}`);
      if (isKidsItem(it.p)) f.push(`${it.role}: children's item "${it.p.title}" in an adult bundle`);
      if (NOVELTY(it.p) && /wedding|office|gift/i.test(c.goal)) f.push(`${it.role}: novelty "${it.p.title}" in a ${c.goal}`);
      if (c.occasionWords && it.role === 'Outfit') {
        const occ = (q) => c.occasionWords.test(`${q.specs?.Occasion || ''} ${q.specs?.Style || ''} ${q.specs?.['Ideal For'] || ''}`);
        const alt = catalog.products.find((q) => fit(q) && q.stock > 0 && !wrongGender(q, c.gender) && !isKidsItem(q) && occ(q) && q.price <= it.p.price * 1.6);
        if (!occ(it.p) && alt) f.push(`Outfit "${it.p.title}" (${it.p.specs?.Occasion}) is not a ${c.goal.split(' ')[0]} outfit; "${alt.title}" (${alt.specs?.Occasion}) is`);
      }
      if (fit) {
        const better = catalog.products.find((q) => q.stock > 0 && fit(q) && q.category_slug === it.p.category_slug && !used.has(q.id) && !wrongGender(q, c.gender) && q.price <= it.p.price && q.rating >= it.p.rating + 0.4 && q.rating_count >= 5);
        if (better) f.push(`${it.role}: "${it.p.title}" (${money(it.p.price)}, ${it.p.rating}★) while "${better.title}" is cheaper and rated higher (${money(better.price)}, ${better.rating}★)`);
      }
      if (it.role === 'Gaming laptop' && !discreteGpu(it.p)) {
        const gpu = catalog.products.find((q) => q.category_slug === 'laptops' && q.stock > 0 && discreteGpu(q) && q.price <= c.budget * 0.85);
        if (gpu) f.push(`gaming laptop is "${it.p.title}" (${it.p.specs?.Graphics}) although "${gpu.title}" has a ${gpu.specs.Graphics} and fits the budget`);
      }
    }
    const text = `${b.explanation} ${b.budgetAdvice?.message || ''}`.toLowerCase();
    for (const s of b.skippedRoles) {
      if (!text.includes(s.toLowerCase())) f.push(`skipped role "${s}" is not explained`);
      const exists = ROLE_FIT[s] && catalog.products.some((q) => ROLE_FIT[s](q) && q.stock > 0 && !wrongGender(q, c.gender));
      const budgetClause = b.explanation.toLowerCase().match(/left out([^.]*)to stay within budget/)?.[1] || '';
      if (ROLE_FIT[s] && !exists && budgetClause.includes(s.toLowerCase())) f.push(`says "${s}" was left out to stay within budget, but the catalog has no ${s.toLowerCase()} at all`);
    }
    if (b.budgetAdvice?.minimumForRequired && b.budgetAdvice.minimumForRequired <= c.budget && b.budgetAdvice.missingRequired.length) f.push(`required ${b.budgetAdvice.missingRequired.join(', ')} missing although the essentials fit the budget`);
    record('bundle', `${name} → ${items.map((it) => `${it.role}: ${it.p.title}`).join('; ')}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ gift finder

const GIFT_CASES = [
  { recipient: 'dad', budget: 30000, interests: ['watches'], gender: 'men', cats: ['mens-watches'] },
  { recipient: 'mom', budget: 20000, interests: ['cooking'], gender: 'women', cats: ['kitchen-accessories'], generous: true },
  { recipient: 'sister', budget: 10000, interests: ['makeup'], gender: 'women', cats: ['beauty'] },
  { recipient: 'brother', budget: 60000, interests: ['gaming'], gender: 'men', kw: /gam(?:e|ing|er)|headphone|earphone|airpods|beats|tablet|ipad/i },
  { recipient: 'my boss', budget: 40000, occasion: 'office' },
  { recipient: 'wife', budget: 60000, occasion: 'anniversary', gender: 'women', occ: ['womens-jewellery', 'womens-watches', 'fragrances', 'womens-bags'] },
  { recipient: 'husband', budget: 100000, interests: ['watches'], gender: 'men', cats: ['mens-watches'] },
  { recipient: 'son', age: 10, budget: 15000, interests: ['sports'], kid: true, gender: 'men', cats: ['sports-accessories'] },
  { recipient: 'daughter', age: 8, budget: 10000, kid: true, gender: 'women' },
  { recipient: 'grandma', budget: 15000, gender: 'women', senior: true },
  { recipient: 'friend', budget: 8000, interests: ['coffee'], cats: ['groceries'] },
  { recipient: 'girlfriend', budget: 25000, occasion: 'valentine', interests: ['jewellery'], gender: 'women', cats: ['womens-jewellery'] },
  { recipient: 'bhai', budget: 20000, occasion: 'eid', gender: 'men', occ: ['fragrances', 'mens-shirts', 'mens-watches'] },
  { recipient: 'nephew', budget: 5000, kid: true, gender: 'men' },
  { recipient: 'colleague', budget: 10000, occasion: 'farewell' },
  { recipient: 'dad', budget: 15000, interests: ['travel'], gender: 'men', cats: ['sunglasses', 'mobile-accessories', 'womens-bags'] },
];
const ADULT_ONLY = new Set(['fragrances', 'womens-jewellery', 'mens-watches', 'womens-watches', 'womens-bags', 'beauty', 'skin-care', 'womens-dresses', 'mens-shirts', 'laptops', 'smartphones']);
const NOT_FOR_SENIORS = /corset|nightclub|party glasses|mini skirt/i;
// fine for a child: sport and play, tablets, headphones, children's clothing (not phone cases, chargers or studio gear)
const kidOk = (p) => isKidsItem(p) || ['sports-accessories', 'tablets'].includes(p.category_slug) || AUDIO(p);
// never a good blind gift: model-specific accessories, chargers, studio gear, household consumables
const UNGIFTABLE = /\bcase\b|charger|battery pack|pedestal|tissue/i;

const auditGift = async () => {
  for (const c of GIFT_CASES) {
    const f = [];
    const r = await buildGift({ recipient: c.recipient, occasion: c.occasion, interests: c.interests || [], age: c.age, budget: { min: null, max: c.budget }, limit: 8 });
    const items = r.items.map((i) => i.product);
    const name = `${c.recipient}${c.occasion ? ` (${c.occasion})` : ''}${c.interests ? ` likes ${c.interests.join(', ')}` : ''}, ${money(c.budget)} → ${items.slice(0, 4).map((p) => p.title).join(', ')}`;
    if (items.length < 4) f.push(`only ${items.length} gift ideas`);
    for (const p of items) {
      if (p.price > c.budget) f.push(`"${p.title}" (${money(p.price)}) is over budget`);
      if (wrongGender(p, c.gender)) f.push(`"${p.title}" is a ${genderOf(p)}'s item for ${c.recipient}`);
      if (c.kid && (ADULT_ONLY.has(p.category_slug) || !kidOk(p))) f.push(`"${p.title}" (${p.category_name}) is not a gift for a child`);
      if (UNGIFTABLE.test(p.title)) f.push(`"${p.title}" is not a gift (model-specific accessory or consumable)`);
      if (/monopod|selfie/i.test(p.title) && !(c.interests || []).some((x) => /photo|travel|vlog|tech/i.test(x))) f.push(`"${p.title}" is an odd gift without a photography interest`);
      if (NOVELTY(p) && !/party|birthday/.test(c.occasion || '')) f.push(`novelty "${p.title}" for a ${c.occasion || 'general'} gift`);
      if (!c.kid && isKidsItem(p)) f.push(`"${p.title}" is a children's item for an adult (${c.recipient})`);
      if (c.senior && NOT_FOR_SENIORS.test(`${p.title} ${p.specs?.Occasion || ''} ${p.specs?.Use || ''}`)) f.push(`"${p.title}" is an odd gift for a grandmother`);
    }
    if (c.cats) {
      const available = catalog.products.filter((p) => c.cats.includes(p.category_slug) && p.stock > 0 && p.price <= c.budget && !wrongGender(p, c.gender) && !(c.kid && ADULT_ONLY.has(p.category_slug)));
      const hits = items.slice(0, 4).filter((p) => c.cats.includes(p.category_slug)).length;
      if (available.length && hits < Math.min(2, available.length)) f.push(`interest ${c.interests.join(', ')} barely reflected: ${hits} of the top 4 match (${available.length} matching items fit the budget)`);
    }
    if (c.kw && items.slice(0, 3).filter((p) => c.kw.test(`${p.title} ${p.specs?.['Ideal For'] || ''} ${p.specs?.Type || ''}`)).length < 2) f.push(`interest ${c.interests.join(', ')} barely reflected in the top 3`);
    if (c.occ) {
      const avail = catalog.products.filter((p) => c.occ.includes(p.category_slug) && p.stock > 0 && p.price <= c.budget && !wrongGender(p, c.gender));
      const hits = items.slice(0, 4).filter((p) => c.occ.includes(p.category_slug)).length;
      if (avail.length >= 2 && hits < 2) f.push(`${c.occasion} gift: only ${hits} of the top 4 are classic ${c.occasion} gifts (${c.occ.join(', ')})`);
    }
    if (!c.gender && items.slice(0, 4).filter((p) => genderOf(p) !== 'unisex').length > 1) f.push(`gender unknown but the top 4 has ${items.slice(0, 4).filter((p) => genderOf(p) !== 'unisex').map((p) => `${genderOf(p)}'s "${p.title}"`).join(', ')}`);
    if (c.generous) {
      const meaningful = catalog.products.some((p) => c.cats.includes(p.category_slug) && p.stock > 0 && p.price >= 0.3 * c.budget && p.price <= c.budget);
      if (meaningful && !items.slice(0, 2).some((p) => p.price >= 0.3 * c.budget)) f.push(`top picks feel cheap for a ${money(c.budget)} gift (${items.slice(0, 2).map((p) => money(p.price)).join(', ')})`);
    }
    // variety: at most 3 of one kind (sports gear counts per sport: a racket and a cricket bat are different gifts)
    const counts = new Map();
    const kindKey = (p) => (p.category_slug === 'sports-accessories' ? `sport:${sportOf(p) || p.title}` : p.category_slug);
    for (const p of items) counts.set(kindKey(p), (counts.get(kindKey(p)) || 0) + 1);
    if ([...counts.values()].some((n) => n > 3)) f.push('more than 3 items of one kind');
    if (!c.cats && items.length >= 6 && counts.size < 3) f.push(`little variety: ${counts.size} categories`);
    record('gift', name, f);
  }
};

// ------------------------------------------------------------------------------------------------ complete the look

const LOOK_BASES = [162, 164, 166, 177, 181, 163, 83, 85, 88, 90, 172, 174, 182, 186, 93, 154, 192];
const LOOK_NON_FASHION = [123, 51, 79];

const auditLook = async () => {
  for (const id of LOOK_BASES) {
    const f = [];
    const base = P(id);
    const r = await completeLook(id, { limit: 8 });
    const look = r.look.map((l) => ({ role: l.role, slug: l.category.slug, p: l.item.product, reasons: l.item.reasons }));
    const name = `${base.title} (${base.color || 'no colour'}, ${money(base.price)}) → ${look.map((l) => `${l.role}: ${l.p.title}`).join('; ')}`;
    if (r.kind !== 'outfit') f.push(`kind is ${r.kind}`);
    if (look.length < 2 && !isKidsItem(base)) f.push(`only ${look.length} pieces`);
    const g = genderOf(base) === 'unisex' ? null : genderOf(base);
    const baseColor = parseColor(base);
    const genders = new Set(look.map((x) => genderOf(x.p)).filter((x) => x !== 'unisex'));
    if (!g && genders.size > 1) f.push(`mixes men's and women's pieces in one look (${look.map((x) => `${x.role}: ${x.p.title}`).join('; ')})`);
    for (const l of [...look.map((x) => x.p), ...r.items.map((i) => i.product)]) {
      if (!isKidsItem(base) && isKidsItem(l)) f.push(`children's item "${l.title}" in an adult look`);
      if (wrongGender(l, g)) f.push(`"${l.title}" is a ${genderOf(l)}'s item for a ${g}'s ${base.category_name.toLowerCase()}`);
      if (l.category_slug === base.category_slug) f.push(`"${l.title}" is from the same category as the base`);
    }
    for (const l of look) {
      const limit = Math.max(5 * base.price, 15000);
      if (l.p.price > limit) f.push(`${l.role}: "${l.p.title}" costs ${money(l.p.price)} for a ${money(base.price)} ${base.category_name.toLowerCase()} (more than 5×)`);
      if (isKidsItem(base) && (l.slug === 'fragrances' || /watches$/.test(l.slug) || l.p.specs?.['Heel Height'])) f.push(`${l.role}: "${l.p.title}" for a children's dress`);
      const h = colorHarmony(baseColor, parseColor(l.p));
      if (h.rule === 'clash') {
        const alt = catalog.products.find((q) => q.category_slug === l.slug && q.stock > 0 && q.id !== l.p.id && !wrongGender(q, g) && colorHarmony(baseColor, parseColor(q)).rule !== 'clash' && q.price <= Math.max(5 * base.price, 15000));
        if (alt) f.push(`${l.role}: ${l.p.color} "${l.p.title}" clashes with ${base.color} although "${alt.title}" (${alt.color}) would go`);
      }
    }
    if (baseColor && !r.palette) f.push('no palette tip although the colour is known');
    record('look', name, f);
  }
  for (const id of LOOK_NON_FASHION) {
    const f = [];
    const base = P(id);
    const r = await completeLook(id, { limit: 6 });
    const items = r.items.map((i) => i.product);
    if (r.kind !== 'complementary') f.push(`kind is ${r.kind}`);
    if (!items.length) f.push('no complementary items');
    for (const p of items) {
      if (p.id === base.id) f.push('suggests the product itself');
      else if (!complementOk(base, p)) f.push(`"${p.title}" (${p.category_slug}) does not go with a ${base.category_name.toLowerCase()}`);
    }
    record('look', `${base.title} (non-fashion) → ${items.slice(0, 4).map((p) => p.title).join(', ')}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ spec explainer

const EXPLAIN_CASES = [
  { id: 121, levels: { Processor: [1, 1], RAM: [1, 1], Storage: [1, 1], Battery: [1, 2], 'Rear Camera': [1, 2] }, notWho: /gamers/ },
  { id: 123, levels: { Processor: [5, 5], RAM: [3, 3], Storage: [3, 3], Display: [4, 5], 'Rear Camera': [4, 5], 'Water Resistance': [4, 5], Network: [4, 5] } },
  { id: 125, levels: { Processor: [1, 1], RAM: [2, 2], Battery: [4, 5], Charging: [3, 5], Display: [1, 3] }, notWho: /gamers/ },
  { id: 128, levels: { Processor: [1, 2], Battery: [4, 5], Storage: [2, 2] } },
  { id: 130, levels: { Processor: [3, 3], RAM: [4, 4], Display: [4, 5] } },
  { id: 133, levels: { Processor: [4, 5], RAM: [4, 4], Storage: [3, 3], Display: [4, 5] } },
  { id: 131, levels: { Storage: [1, 1], Processor: [2, 3] } },
  { id: 160, levels: { Processor: [5, 5], Display: [5, 5], RAM: [4, 5] } },
  { id: 161, levels: { Processor: [1, 2], RAM: [1, 2], Storage: [1, 1] }, notWho: /gamers/ },
  { id: 78, levels: { Processor: [4, 5], RAM: [4, 4], Storage: [3, 3], Display: [4, 5], 'Battery Life': [4, 5], Weight: [3, 4] } },
  { id: 79, levels: { Graphics: [4, 5], Weight: [1, 2], 'Battery Life': [1, 2], Display: [4, 5] }, who: /gamers/ },
  { id: 81, levels: { Processor: [2, 3], Graphics: [1, 2] }, notWho: /gamers/ },
  { id: 80, levels: { Weight: [4, 5], 'Battery Life': [4, 4] } },
  { id: 100, levels: { 'Noise Cancellation': [0, 1], Battery: [2, 3] } },
  { id: 101, levels: { 'Noise Cancellation': [5, 5], Battery: [4, 5] } },
  { id: 106, levels: { 'Water Resistance': [3, 4] } },
  { id: 93, levels: { 'Water Resistance': [1, 2], Movement: [2, 3], Crystal: [2, 3] } },
  { id: 98, levels: { Movement: [5, 5], Crystal: [4, 5], 'Water Resistance': [5, 5] } },
  { id: 7, levels: { Concentration: [4, 4], Longevity: [4, 5] } },
  { id: 6, levels: { Concentration: [3, 3], Longevity: [2, 3] } },
  { id: 113, levels: { Engine: [1, 2] } },
  { id: 114, levels: { Engine: [4, 5] } },
];
const PRAISE = /\b(?:plenty|excellent|flagship|top-end|effortless|powerful|great|superb|outstanding)\b/i;
const DISS = /\b(?:basic|slow|only for|struggles?|weak|outdated|poor)\b/i;

const explainGeneric = (p, e) => {
  const f = [];
  const keys = new Set([...Object.keys(p.specs || {}), 'Warranty']);
  for (const s of e.specs) {
    if (!keys.has(s.key)) f.push(`invented spec "${s.key}"`);
    const num = String(s.value).match(/\d+(?:\.\d+)?/);
    const shown = (`${s.title} ${s.meaning}`.replace(/(\d),(\d{3})/g, '$1$2').match(/\d+(?:\.\d+)?/g) || []).map(Number);
    if (num && /^\d/.test(String(s.value).trim()) && !shown.includes(Number(num[0]))) f.push(`${s.key} "${s.value}" explained without its number: "${s.title}"`);
    if (s.level && s.level <= 2 && PRAISE.test(`${s.title} ${s.meaning}`)) f.push(`${s.key} "${s.value}" is level ${s.level} but praised: "${s.title} — ${s.meaning}"`);
    if (s.level && s.level >= 4 && DISS.test(`${s.title} ${s.meaning}`)) f.push(`${s.key} "${s.value}" is level ${s.level} but described as weak: "${s.meaning}"`);
  }
  return f;
};

const auditExplain = async () => {
  for (const c of EXPLAIN_CASES) {
    const p = P(c.id);
    const e = explainProduct(p);
    const f = explainGeneric(p, e);
    for (const [key, [lo, hi]] of Object.entries(c.levels)) {
      const s = e.specs.find((x) => x.key === key);
      const lv = s?.level || 0;
      if (!s && p.specs?.[key]) f.push(`${key} "${p.specs[key]}" is not explained`);
      else if (s && (lv < lo || lv > hi)) f.push(`${key} "${s.value}" rated L${lv} (${s.levelLabel || 'no level'}), expected ${lo === hi ? `L${lo}` : `L${lo}-${hi}`}: "${s.title}"`);
    }
    if (c.who && !c.who.test(e.whoFor.join(', '))) f.push(`"who it's for" misses ${c.who}: ${e.whoFor.join(', ') || '(none)'}`);
    if (c.notWho && c.notWho.test(e.whoFor.join(', '))) f.push(`"who it's for" wrongly says ${e.whoFor.join(', ')}`);
    record('explain', `${p.title} — ${e.summary.slice(0, 110)}…`, f);
  }
  // sweep: generic checks over every product with specs
  const f = [];
  for (const p of catalog.products) for (const x of explainGeneric(p, explainProduct(p))) f.push(`${p.title}: ${x}`);
  record('explain', `generic sweep over all ${catalog.products.length} products (invented specs, missing numbers, praise/level mismatches)`, f.slice(0, 12).concat(f.length > 12 ? [`…and ${f.length - 12} more`] : []));
};

// ------------------------------------------------------------------------------------------------ product q&a

const UNKNOWN = /couldn'?t find|not listed|isn'?t listed|doesn'?t (?:list|mention|say)|don'?t have|no (?:information|details?)|not mentioned/i;
const QA_CASES = [
  { id: 123, q: 'is it waterproof', want: /^yes\b.*IP68/i },
  { id: 125, q: 'is it waterproof', want: UNKNOWN, not: /^yes/i },
  { id: 93, q: 'is it waterproof', want: /30 m|splash/i, not: /^yes —/i },
  { id: 78, q: 'how much RAM does it have', want: /16 GB/ },
  { id: 130, q: 'how much ram', want: /8 GB/ },
  { id: 133, q: 'how much storage does it have', want: /128 GB/ },
  { id: 125, q: 'how big is the battery', want: /5000 mAh/ },
  { id: 100, q: 'how long does the battery last', want: /5 hours|24 hours/ },
  { id: 101, q: 'does it have noise cancellation', want: /^yes\b.*active noise/i },
  { id: 100, q: 'does it have noise cancellation', want: /^no\b/i },
  { id: 186, q: 'what is the heel height', want: /7\.5 cm/ },
  { id: 12, q: 'what size is it', want: /220 x 95/ },
  { id: 79, q: 'is it good for gaming', want: /RTX 2060|gaming/i, not: UNKNOWN },
  { id: 121, q: 'is it good for gaming', want: /\bno\b|not (?:great|ideal|suited|built)|basic|light|older|struggle/i, not: /^yes/i },
  { id: 123, q: 'does it come with warranty', want: /3 year/i },
  { id: 80, q: 'does it come with warranty', want: /^no\b|no warranty/i, not: /^yes/i },
  { id: 123, q: 'does it support 5g', want: /^yes\b.*5G/i },
  { id: 161, q: 'does it support 5g', want: /^no\b|UNKNOWN|not listed|lte/i, not: /^yes/i },
  { id: 7, q: 'how long does the scent last', want: /8 to 10 hours/ },
  { id: 6, q: 'is it for men', want: /unisex/i },
  { id: 113, q: 'what is the mileage', want: /45 km\/l/ },
  { id: 116, q: 'is it automatic', want: /^yes\b.*(?:CVT|automatic)/i },
  { id: 114, q: 'is it automatic', want: /^no\b.*manual/i },
  { id: 160, q: 'does it come with a stylus', want: /^yes\b.*S Pen/i },
  { id: 129, q: 'what is the price', want: /Rs 83,999/ },
  { id: 132, q: 'is it in stock', want: /out of stock/i },
  { id: 123, q: 'what colour is it', want: /Sierra Blue/i },
  { id: 121, q: 'does it have face id', want: /^no\b|UNKNOWN|couldn'?t find|not listed/i, not: /^yes/i },
  { id: 124, q: 'does it have face id', want: /^yes\b.*face id/i },
  { id: 78, q: 'how heavy is it', want: /1\.6 kg/ },
  { id: 99, q: 'does it work with alexa', want: /^yes\b.*alexa/i },
  { id: 122, q: 'does it support wireless charging', want: /^no\b|wired|UNKNOWN|not listed/i, not: /^yes/i },
  { id: 51, q: 'is it dishwasher safe', want: /^yes\b.*dishwasher/i },
  { id: 36, q: 'is it gluten free', want: /^yes\b.*gluten/i },
  { id: 66, q: 'what is the capacity', want: /20 L/ },
  { id: 175, q: 'is it real leather', want: /faux|PU/i, not: /^yes/i },
];

const auditQa = async () => {
  for (const c of QA_CASES) {
    const f = [];
    const p = P(c.id);
    const r = await qa.ask(c.id, c.q);
    const want = c.want.source.includes('UNKNOWN') ? new RegExp(c.want.source.replace('UNKNOWN', UNKNOWN.source), 'i') : c.want;
    if (!want.test(r.answer)) f.push(`answer does not match ${c.want}`);
    if (c.not && c.not.test(r.answer)) f.push(`answer should not match ${c.not}`);
    if (!UNKNOWN.test(r.answer) && !r.evidence.length) f.push('no evidence cited');
    record('qa', `${p.title}: "${c.q}" → ${r.answer.replace(/\*\*/g, '').slice(0, 120)}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ review summary

const REVIEW_IDS = [123, 125, 82, 10, 1, 161, 79, 14, 173, 186, 114, 36, 98, 133, 51];

const auditReviews = async () => {
  for (const id of REVIEW_IDS) {
    const f = [];
    const p = P(id);
    const s = await reviewSummary(id);
    const reviews = await models.reviewsFor(id);
    const avg = reviews.reduce((a, r) => a + r.rating, 0) / (reviews.length || 1);
    if (s.reviewCount !== reviews.length) f.push(`reviewCount ${s.reviewCount} but ${reviews.length} reviews`);
    if (avg >= 4.2 && !/positive/i.test(s.sentiment.label)) f.push(`average ${avg.toFixed(1)}★ but labelled "${s.sentiment.label}"`);
    if (avg <= 2.8 && /positive/i.test(s.sentiment.label)) f.push(`average ${avg.toFixed(1)}★ but labelled "${s.sentiment.label}"`);
    if (avg < 3.9 && s.sentiment.label === 'Very positive') f.push(`average ${avg.toFixed(1)}★ but labelled "Very positive"`);
    const dict = aspectsFor(p.category_slug);
    const keyOf = (label) => Object.keys(LABELS).find((k) => LABELS[k] === label) || label;
    const mentioning = (label) => reviews.filter((r) => detectAspects(`${r.title || ''}. ${r.comment || ''}`, dict).includes(keyOf(label)));
    // a pro needs a happy reviewer (4-5★) or a clearly positive remark about it in a middling review
    const POSITIVE = /impressive|great|excellent|love|good|comfortable|solid|premium|fast|quick|amazing|perfect|nice|lasts all day|beautiful|stylish|sturdy|smooth|plus side/i;
    const praised = (label) => mentioning(label).some((r) => r.rating >= 4 || (String(r.comment || '').split(/(?<=[.!?])\s+/).some((x) => detectAspects(x, dict).includes(keyOf(label)) && POSITIVE.test(x) && !/\b(?:not|poor|cheap|but)\b/i.test(x))));
    for (const pro of s.pros) if (!praised(pro.aspect)) f.push(`pro "${pro.aspect}" but no 4-5★ review mentions it (${mentioning(pro.aspect).map((r) => `${r.rating}★`).join(', ')})`);
    for (const con of s.cons) if (!mentioning(con.aspect).some((r) => r.rating <= 3) && !mentioning(con.aspect).some((r) => /\b(?:but|only gripe|however|though|complain|wish)\b/i.test(r.comment || ''))) f.push(`con "${con.aspect}" but only happy 4-5★ reviews mention it, without any criticism`);
    const pct = s.summary.match(/(\d+)% of (\d+) reviews are positive/);
    if (pct && Number(pct[2]) !== reviews.length) f.push('summary review count is wrong');
    // quotes: a balanced pair — when real criticism exists (a 1-2★ review with text), one quote should show it
    const sources = s.highlights.map((h) => reviews.find((r) => (r.comment || '').replace(/\s+/g, ' ').startsWith(h.replace(/…$/, '').slice(0, 40))));
    const critical = reviews.filter((r) => r.rating <= 2 && (r.comment || '').length > 12);
    if (critical.length && !sources.some((r) => r && r.rating <= 3)) f.push(`${critical.length} critical review(s) (e.g. ${critical[0].rating}★ "${critical[0].comment.slice(0, 50)}") but no critical quote in the highlights`);
    if (sources.filter(Boolean).length === 2 && sources[0].rating < sources[1].rating) f.push('the "positive" quote comes from a lower-rated review than the critical one');
    record('reviews', `${p.title} (${reviews.length} reviews, avg ${avg.toFixed(1)}★) → ${s.sentiment.label}; pros ${s.pros.map((x) => x.aspect).join(', ') || '-'}; cons ${s.cons.map((x) => x.aspect).join(', ') || '-'}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ similar / bought together (recommender.js — report only)

const REC_BASES = [123, 79, 100, 88, 177, 7, 51, 36, 14, 140, 113, 172, 93, 1];

const auditSimilar = async () => {
  for (const id of REC_BASES) {
    const f = [];
    const base = P(id);
    const items = (await recommender.similar(id, 8)).map((r) => r.product);
    for (const p of items.slice(0, 4)) {
      if (p.id === base.id) f.push('suggests the product itself');
      else if (p.category_slug !== base.category_slug && !(p.department_slug === base.department_slug && sameSubtype(base, p))) f.push(`"${p.title}" (${p.category_slug}) is not the same kind of product as a ${base.category_name.toLowerCase()}`);
      if (wrongGender(p, genderOf(base) === 'unisex' ? null : genderOf(base))) f.push(`"${p.title}" is for ${genderOf(p)}`);
    }
    record('similar', `${base.title} → ${items.slice(0, 4).map((p) => p.title).join(', ')}`, f);
  }
};

const auditBoughtTogether = async () => {
  for (const id of REC_BASES) {
    const f = [];
    const base = P(id);
    const items = (await recommender.boughtTogether(id, 6)).map((r) => r.product);
    const g = genderOf(base) === 'unisex' ? null : genderOf(base);
    for (const p of items) {
      if (p.id === base.id) f.push('suggests the product itself');
      else if (!complementOk(base, p)) f.push(`"${p.title}" (${p.category_slug}) is not a complement to a ${base.category_name.toLowerCase()}`);
      if (wrongGender(p, g)) f.push(`"${p.title}" is for ${genderOf(p)}`);
    }
    record('boughtTogether', `${base.title} → ${items.slice(0, 4).map((p) => p.title).join(', ')}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ cart insights (cart stubbed in memory)

const CART_CASES = [
  { items: [[123, 1]] }, { items: [[79, 1], [100, 1]] }, { items: [[97, 1]] }, { items: [[21, 2], [31, 3]] },
  { items: [[181, 1]] }, { items: [[51, 2]] }, { items: [[14, 1]] }, { items: [[8, 1], [4, 1]] }, { items: [[133, 1], [108, 1]] },
  { items: [[90, 1]] }, { items: [[59, 2]] }, { items: [[5, 1]], coupon: 'WELCOME10' }, { items: [[65, 1], [62, 1]], coupon: 'FLAT500' }, { items: [[130, 1]] }, { items: [[94, 1]] },
];

const explainedDrop = (base, alt) => {
  const a = explainProduct(base).specs.filter((s) => s.level && !/warranty/i.test(s.key));
  const b = new Map(explainProduct(alt).specs.filter((s) => s.level).map((s) => [s.key, s.level]));
  const shared = a.filter((s) => b.has(s.key));
  if (shared.length < 2) return null;
  const drops = shared.map((s) => ({ key: s.key, drop: s.level - b.get(s.key) }));
  return { avg: drops.reduce((x, d) => x + d.drop, 0) / drops.length, worst: drops.sort((x, y) => y.drop - x.drop)[0] };
};

const auditCart = async () => {
  const original = models.cartSnapshot;
  try {
    for (const c of CART_CASES) {
      const f = [];
      const rows = c.items.map(([id, quantity]) => ({ ...P(id), quantity }));
      models.cartSnapshot = async () => ({ items: rows, couponCode: c.coupon || null });
      const r = await cartInsights(-1);
      const subtotal = rows.reduce((s, x) => s + x.price * x.quantity, 0);
      if (r.subtotal !== subtotal) f.push(`subtotal ${r.subtotal} ≠ ${subtotal}`);
      const inCart = new Set(rows.map((x) => x.id));
      for (const s of r.savings) {
        const base = P(s.productId);
        const alt = s.alternative.product;
        const qty = rows.find((x) => x.id === base.id).quantity;
        if (alt.category_slug !== base.category_slug) f.push(`cheaper alternative "${alt.title}" is a different kind of product than "${base.title}"`);
        if (alt.price >= base.price) f.push(`alternative "${alt.title}" is not cheaper`);
        if (s.save !== (base.price - alt.price) * qty) f.push(`savings math wrong: says ${money(s.save)}, real ${money((base.price - alt.price) * qty)}`);
        if (inCart.has(alt.id) || alt.stock <= 0) f.push(`alternative "${alt.title}" is in the cart or out of stock`);
        const d = explainedDrop(base, alt);
        if (d && (d.avg > 1 || d.worst.drop >= 3)) f.push(`"${alt.title}" is a clear downgrade from "${base.title}", not a near-equivalent (${d.worst.key} drops ${d.worst.drop} levels, avg ${d.avg.toFixed(1)})`);
        if (alt.rating < base.rating - 0.3) f.push(`alternative rated ${alt.rating}★ vs ${base.rating}★`);
      }
      const coupon = c.coupon ? await db('coupons').where({ code: c.coupon }).first() : null;
      let discount = coupon && subtotal >= Number(coupon.min_order_amount || 0) ? (coupon.discount_type === 'percent' ? Math.round((subtotal * Number(coupon.value)) / 100) : Math.round(Number(coupon.value))) : 0;
      if (coupon?.max_discount != null) discount = Math.min(discount, Number(coupon.max_discount));
      const payable = subtotal - discount;
      if (payable < FREE_SHIPPING_THRESHOLD) {
        const remaining = FREE_SHIPPING_THRESHOLD - payable;
        if (!r.freeShippingGap) f.push('no free-shipping gap although below the threshold');
        else {
          if (r.freeShippingGap.remaining !== remaining) f.push(`free-shipping gap says ${money(r.freeShippingGap.remaining)}, real gap ${money(remaining)}${discount ? ` (after the ${money(discount)} coupon)` : ''}`);
          for (const p of r.freeShippingGap.suggestions) if (p.price < remaining || inCart.has(p.id) || p.stock <= 0) f.push(`gap filler "${p.title}" (${money(p.price)}) does not close the ${money(remaining)} gap`);
          if (!r.summary.includes(money(remaining))) f.push('summary does not state the real gap');
        }
      } else if (r.freeShippingGap) f.push('free-shipping gap shown although the cart already qualifies');
      for (const x of r.completeTheSet) {
        const p = x.product;
        if (inCart.has(p.id)) f.push(`complete-the-set suggests "${p.title}" which is already in the cart`);
        if (!rows.some((b) => complementOk(b, p))) f.push(`complete-the-set "${p.title}" (${p.category_slug}) does not go with the cart`);
        if (rows.some((b) => incompatible(b, p))) f.push(`complete-the-set "${p.title}" is not compatible with the ${rows.find((b) => incompatible(b, p)).title}`);
        if (rows.some((b) => b.category_slug === p.category_slug && p.category_slug !== 'groceries' && (DEVICES.has(p.category_slug) || sameSubtype(b, p)))) f.push(`complete-the-set "${p.title}" is another ${p.category_name.toLowerCase()} like one already in the cart`);
        const g = rows.map(genderOf).find((x2) => x2 !== 'unisex');
        if (wrongGender(p, g)) f.push(`complete-the-set "${p.title}" is for ${genderOf(p)}`);
      }
      const desc = `${rows.map((x) => `${x.quantity}× ${x.title}`).join(' + ')}${c.coupon ? ` (coupon ${c.coupon})` : ''} → savings: ${r.savings.map((s) => s.alternative.product.title).join(', ') || '-'}; set: ${r.completeTheSet.map((x) => x.product.title).join(', ') || '-'}`;
      record('cart', desc, f);
    }
  } finally {
    models.cartSnapshot = original;
  }
};

// ------------------------------------------------------------------------------------------------ shopping dna

const PERSONA_RULES = {
  'The Tech Enthusiast': (t, d) => d.electronics >= 0.4,
  'The Smart Saver': (t) => t.price >= 0.55 || t.deal >= 0.5,
  'The Brand Loyalist': (t) => t.brand >= 0.5,
  'The Trendsetter': (t) => t.trend >= 0.5,
  'The Quality Connoisseur': (t) => t.quality >= 0.55,
  'The Curious Explorer': (t) => t.breadth >= 0.5,
  'The Style Maven': (t, d) => d.fashion >= 0.4,
  'The Beauty Buff': (t, d) => d.beauty >= 0.4,
  'The Home Maker': (t, d) => d.home + d.groceries >= 0.4,
  'The Careful Researcher': (t) => t.research >= 0.6,
  'The Fresh Explorer': () => true,
};
const DEPT = { electronics: 'electronics', fashion: 'fashion', 'beauty-personal-care': 'beauty', 'home-living': 'home', groceries: 'groceries', 'sports-outdoors': 'sports', automotive: 'automotive' };

const dnaPersonas = [
  { name: 'beauty lover', purchases: [1, 2, 4, 5, 7, 8], wishlist: [9, 10, 119], expect: ['The Beauty Buff'] },
  { name: 'tech fan', purchases: [123, 78, 100], views: [79, 80, 133, 160, 101, 130], wishlist: [159], expect: ['The Tech Enthusiast'] },
  { name: 'bargain hunter', purchases: [21, 31, 26, 58, 74, 151, 146, 111, 185, 157], expect: ['The Smart Saver'] },
  { name: 'Apple loyalist', purchases: [121, 122, 123, 124, 100, 101, 104, 78, 159], expect: ['The Brand Loyalist', 'The Tech Enthusiast'], brandMin: 0.8 },
  { name: 'luxury watch buyer', purchases: [95, 96, 97, 98], wishlist: [94], expect: ['The Quality Connoisseur', 'The Style Maven', 'The Brand Loyalist'], priceMax: 0.45 },
  { name: 'home maker', purchases: [48, 52, 64, 66, 20, 38, 43, 47], expect: ['The Home Maker'] },
  { name: 'brand-new user', purchases: [], expect: ['The Fresh Explorer'] },
];

const checkDna = (dna, events, f) => {
  const t = Object.fromEntries(dna.traits.map((x) => [x.key, x.value]));
  const dw = {};
  let total = 0;
  for (const e of events) {
    const p = P(e.id);
    const w = TYPE_WEIGHTS[e.type] || 0.5;
    dw[DEPT[p.department_slug]] = (dw[DEPT[p.department_slug]] || 0) + w;
    total += w;
  }
  const d = Object.fromEntries(['electronics', 'fashion', 'beauty', 'home', 'groceries', 'sports', 'automotive'].map((k) => [k, total ? (dw[k] || 0) / total : 0]));
  const top = Object.entries(d).sort((a, b) => b[1] - a[1])[0];
  if (dna.persona.title === 'The Curious Explorer' && top && top[1] >= 0.45) f.push(`persona "The Curious Explorer" although ${Math.round(top[1] * 100)}% of the activity is ${top[0]}`);
  const rule = PERSONA_RULES[dna.persona.title];
  if (rule && !rule(t, d)) f.push(`persona "${dna.persona.title}" is not supported by the traits (${dna.traits.map((x) => `${x.key} ${x.value}`).join(', ')}; departments ${Object.entries(d).filter(([, v]) => v).map(([k, v]) => `${k} ${v.toFixed(2)}`).join(', ')})`);
  const price = dna.traits.find((x) => x.key === 'price');
  if (price && price.value > 0.6 && !/lower/.test(price.description)) f.push('price trait description contradicts its value');
  if (price && price.value < 0.4 && !/upper/.test(price.description)) f.push('price trait description contradicts its value');
  const brand = dna.traits.find((x) => x.key === 'brand');
  if (dna.topBrands[0] && !brand.description.includes(dna.topBrands[0].name)) f.push('brand trait names a different brand than topBrands');
  if (events.length) {
    const prices = events.map((e) => P(e.id).price);
    if (dna.priceBand.min !== Math.min(...prices) || dna.priceBand.max !== Math.max(...prices)) f.push(`price band ${dna.priceBand.min}-${dna.priceBand.max} does not match the history (${Math.min(...prices)}-${Math.max(...prices)})`);
  }
  return { t, d };
};

const auditDna = async () => {
  // the seeded demo user, straight from the database
  const demo = await db('users').where({ email: 'demo@cartwise.app' }).first('id');
  if (demo) {
    const f = [];
    const dna = await shoppingDna(demo.id);
    const sig = await models.userSignals(demo.id);
    const events = [
      ...sig.interactions.filter((i) => i.type !== 'pass').map((i) => ({ id: i.product_id, type: i.type })),
      ...sig.wishlist.map((w) => ({ id: w.product_id, type: 'wishlist' })),
      ...sig.cart.map((c) => ({ id: c.product_id, type: 'cart' })),
      ...sig.purchases.map((p) => ({ id: p.product_id, type: 'purchase' })),
    ].filter((e) => P(e.id));
    checkDna(dna, events, f);
    if (dna.signals.views !== sig.interactions.filter((i) => i.type === 'view').length) f.push('view count does not match');
    if (dna.signals.purchases !== sig.purchases.length || dna.signals.wishlist !== sig.wishlist.length) f.push('purchase/wishlist counts do not match');
    const passed = new Set(sig.interactions.filter((i) => i.type === 'pass').map((i) => i.product_id));
    const engaged = new Set(events.map((e) => e.id));
    const onlyPassedCats = dna.topCategories.filter((c2) => ![...engaged].some((id) => P(id).category_slug === c2.slug) && [...passed].some((id) => P(id)?.category_slug === c2.slug));
    if (onlyPassedCats.length) f.push(`top categories include ${onlyPassedCats.map((x) => x.name).join(', ')}, which the user only swiped away`);
    const { d: dd } = checkDna(dna, events, []);
    record('dna', `demo user (${Object.entries(dd).filter(([, v]) => v >= 0.05).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${Math.round(v * 100)}%`).join(', ')}) → ${dna.persona.title} (runner-up ${dna.persona.runnerUp || '-'}); top ${dna.topCategories.slice(0, 3).map((x) => x.name).join(', ')}`, f);
  }
  const origSignals = models.userSignals;
  const origExtras = models.profileExtras;
  try {
    for (const s of dnaPersonas) {
      const f = [];
      const now = new Date();
      models.userSignals = async () => ({
        user: { id: -1, name: 'Audit', preferences: { interests: ['smartphones'] } },
        interactions: (s.views || []).map((id) => ({ product_id: id, type: 'view', created_at: now })),
        wishlist: (s.wishlist || []).map((id) => ({ product_id: id, created_at: now })),
        cart: [],
        purchases: s.purchases.map((id) => ({ product_id: id, created_at: now })),
      });
      models.profileExtras = async () => ({ orders: { count: s.purchases.length ? 2 : 0, with_coupon: 0 }, searches: [], conversations: [] });
      const dna = await shoppingDna(-1);
      const events = [...(s.views || []).map((id) => ({ id, type: 'view' })), ...(s.wishlist || []).map((id) => ({ id, type: 'wishlist' })), ...s.purchases.map((id) => ({ id, type: 'purchase' }))];
      const { t } = checkDna(dna, events, f);
      if (!s.expect.includes(dna.persona.title)) f.push(`persona "${dna.persona.title}", expected ${s.expect.join(' or ')}`);
      if (s.brandMin && t.brand < s.brandMin) f.push(`brand loyalty ${t.brand} for an all-Apple history`);
      if (s.priceMax !== undefined && t.price > s.priceMax) f.push(`price sensitivity ${t.price} for someone who only buys luxury watches`);
      record('dna', `${s.name} → ${dna.persona.title} (runner-up ${dna.persona.runnerUp || '-'})`, f);
    }
  } finally {
    models.userSignals = origSignals;
    models.profileExtras = origExtras;
  }
};

// ------------------------------------------------------------------------------------------------ guided finder

const auditFinder = async () => {
  const flows = await finder.getFlows();
  const budgetsOf = (key) => flows.find((x) => x.key === key).questions.find((q) => q.type === 'budget').options.filter((o) => o.value !== 'any');
  const run = async (department, answers) => (await finder.runFinder({ department, answers, userId: null }));
  const avg = (items) => items.reduce((s, i) => s + i.product.price, 0) / (items.length || 1);
  const cases = [
    ['phones: lowest vs highest budget bracket', async (f) => {
      const b = budgetsOf('electronics');
      const lo = await run('electronics', { type: 'smartphones', budget: b[0].value });
      const hi = await run('electronics', { type: 'smartphones', budget: b[b.length - 1].value });
      if (!(avg(lo.products) < avg(hi.products))) f.push(`lower budget is not cheaper (avg ${money(avg(lo.products))} vs ${money(avg(hi.products))})`);
      const max = Number(b[0].value.split('-')[1]);
      if (!lo.fallback) for (const i of lo.products) if (i.product.price > max) f.push(`"${i.product.title}" ${money(i.product.price)} is above ${money(max)}`);
      return `${lo.products.length} vs ${hi.products.length} results`;
    }],
    ['phones from Samsung', async (f) => {
      const r = await run('electronics', { type: 'smartphones', brand: 'samsung' });
      for (const i of r.products) if (i.product.brand_name !== 'Samsung') f.push(`"${i.product.title}" is not Samsung`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['laptops for gaming', async (f) => {
      const r = await run('electronics', { type: 'laptops', use: ['gaming'] });
      if (!r.products[0] || !discreteGpu(r.products[0].product)) f.push(`top laptop for gaming is "${r.products[0]?.product.title}" (${r.products[0]?.product.specs?.Graphics}), not the one with a gaming GPU`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['phones for photography', async (f) => {
      const r = await run('electronics', { type: 'smartphones', use: ['camera'] });
      const top = r.products.slice(0, 3).map((i) => levelOf(i.product, 'Rear Camera'));
      if (Math.max(...top) < 4) f.push(`no strong camera in the top 3 (levels ${top.join(', ')})`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['phones with long battery life', async (f) => {
      const r = await run('electronics', { type: 'smartphones', use: ['battery'] });
      const top = r.products.slice(0, 3).map((i) => levelOf(i.product, 'Battery'));
      if (top.filter((l) => l >= 4).length < 2) f.push(`top 3 battery levels ${top.join(', ')}`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['women\'s shoes', async (f) => {
      const r = await run('fashion', { for: 'women', category: 'shoes' });
      for (const i of r.products) if (i.product.category_slug !== 'womens-shoes') f.push(`"${i.product.title}" is ${i.product.category_slug}`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['men\'s watches, lowest budget', async (f) => {
      const b = budgetsOf('fashion');
      const r = await run('fashion', { for: 'men', category: 'watches', budget: b[0].value });
      for (const i of r.products) if (i.product.category_slug !== 'mens-watches') f.push(`"${i.product.title}" is ${i.product.category_slug}`);
      return `${b[0].label}: ${r.products.map((i) => `${i.product.title} ${money(i.product.price)}`).slice(0, 3).join(', ')}`;
    }],
    ['women\'s clothing in red', async (f) => {
      const r = await run('fashion', { for: 'women', category: 'clothing', color: 'red' });
      if (!r.products[0] || !/red/i.test(`${r.products[0].product.color} ${r.products[0].product.title}`)) f.push(`top result "${r.products[0]?.product.title}" (${r.products[0]?.product.color}) is not red`);
      for (const i of r.products) if (genderOf(i.product) === 'men') f.push(`"${i.product.title}" is men's`);
      return r.products.map((i) => `${i.product.title} (${i.product.color})`).slice(0, 3).join(', ');
    }],
    ['fragrances, lowest budget', async (f) => {
      const b = budgetsOf('beauty');
      const r = await run('beauty', { type: 'fragrances', budget: b[0].value });
      const max = Number(b[0].value.split('-')[1]);
      for (const i of r.products) {
        if (i.product.category_slug !== 'fragrances') f.push(`"${i.product.title}" is not a fragrance`);
        if (!r.fallback && i.product.price > max) f.push(`"${i.product.title}" over ${money(max)}`);
      }
      return `${b[0].label}: ${r.products.map((i) => i.product.title).slice(0, 3).join(', ')}${r.fallback ? ' (fallback)' : ''}`;
    }],
    ['kitchen', async (f) => {
      const r = await run('home', { room: 'kitchen-accessories' });
      for (const i of r.products) if (i.product.category_slug !== 'kitchen-accessories') f.push(`"${i.product.title}" is ${i.product.category_slug}`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['bedroom', async (f) => {
      const r = await run('home', { room: 'bedroom' });
      const top = r.products.slice(0, 2).map((i) => i.product);
      if (!top.length || !top.every((p) => /bed/i.test(p.title))) f.push(`top results are ${top.map((p) => p.title).join(', ')}, not bedroom furniture`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['cricket gear', async (f) => {
      const r = await run('sports', { activity: 'cricket' });
      const top = r.products.slice(0, 3).map((i) => i.product);
      for (const p of top) if (!/cricket/i.test(p.title)) f.push(`"${p.title}" in the top 3 for cricket`);
      return top.map((p) => p.title).join(', ');
    }],
    ['fruits', async (f) => {
      const r = await run('groceries', { type: ['fruits'] });
      const top = r.products.slice(0, 3).map((i) => i.product);
      for (const p of top) if (!/apple|kiwi|strawberr|mulberr|lemon|fruit|banana|orange|mango/i.test(p.title)) f.push(`"${p.title}" in the top 3 for fruits`);
      return top.map((p) => p.title).join(', ');
    }],
    ['car vs motorcycle', async (f) => {
      const car = await run('automotive', { type: 'vehicle' });
      const bike = await run('automotive', { type: 'motorcycle' });
      for (const i of car.products) if (i.product.category_slug !== 'vehicle') f.push(`car finder shows "${i.product.title}"`);
      for (const i of bike.products) if (i.product.category_slug !== 'motorcycle') f.push(`motorcycle finder shows "${i.product.title}"`);
      return `${car.products.length} cars, ${bike.products.length} bikes`;
    }],
    ['motorcycle for daily commute', async (f) => {
      const r = await run('automotive', { type: 'motorcycle', use: 'commute city' });
      const top = r.products[0]?.product;
      const cc = Number(String(top?.specs?.Engine || '').match(/(\d+)\s*cc/)?.[1] || 0);
      if (!top || cc > 250) f.push(`top commuter pick is "${top?.title}" (${top?.specs?.Engine})`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
    ['makeup', async (f) => {
      const r = await run('beauty', { type: 'beauty' });
      for (const i of r.products) if (i.product.category_slug !== 'beauty') f.push(`"${i.product.title}" is ${i.product.category_slug}`);
      return r.products.map((i) => i.product.title).slice(0, 3).join(', ');
    }],
  ];
  for (const [name, fn] of cases) {
    const f = [];
    const detail = await fn(f);
    record('finder', `${name} → ${detail}`, f);
  }
};

// ------------------------------------------------------------------------------------------------ smart search wrapper (interpretation, chips, budget honesty)

const SEARCH_CASES = [
  { q: 'red dress under 10000', chips: ['color', 'budget'], max: 10000 }, { q: 'samsung phone', chips: ['brand'] },
  { q: 'gift for dad under 20k', chips: ['recipient', 'budget'], max: 20000 }, { q: 'cheap laptop', chips: [] },
  { q: 'watches for women', chips: ['gender'] }, { q: 'running shoes for men', chips: ['gender'] }, { q: 'perfume', chips: [] },
  { q: 'iphone 13 pro', chips: [] }, { q: 'kitchen stuff below 5000', chips: ['budget'], max: 5000 },
];

const auditSearch = async () => {
  for (const c of SEARCH_CASES) {
    const f = [];
    const r = await engine.smartSearch(c.q, { limit: 12 });
    const types = new Set(r.interpretation.chips.map((x) => x.type));
    for (const t of c.chips) if (!types.has(t)) f.push(`no ${t} chip`);
    if (r.products.length && /^No matches/.test(r.interpretation.text)) f.push('says "No matches" although products are shown');
    if (!r.products.length && !/^No matches/.test(r.interpretation.text)) f.push('shows no products but the text does not say so');
    if (r.total < r.products.length) f.push('total is smaller than the products shown');
    if (c.max && !r.fallback) for (const p of r.products) if (p.price > c.max) f.push(`"${p.title}" ${money(p.price)} breaks the ${money(c.max)} budget without saying so`);
    if (c.max && r.fallback && !/budget|above|over|relax|closest|no .* under/i.test(r.interpretation.text)) f.push('budget was relaxed but the interpretation does not say so');
    record('search', `"${c.q}" → ${r.interpretation.text} [${r.interpretation.chips.map((x) => x.label).join(', ')}]`, f);
  }
};

// ------------------------------------------------------------------------------------------------ snap & find

const auditVisual = async () => {
  const sharp = require('sharp');
  const visual = require('../api/modules/ai/engine/visual');
  const sample = catalog.products.filter((p, i) => i % 4 === 0 && p.thumbnail_url?.startsWith('/'));
  let exact = 0;
  let exact3 = 0;
  let sameCat = 0;
  let n = 0;
  for (const p of sample) {
    const file = path.join(ROOT, p.thumbnail_url);
    if (!fs.existsSync(file)) continue;
    // a "phone photo" of the product: off-centre crop, mirrored, smaller, recompressed as jpeg
    const meta = await sharp(file).metadata();
    const w = Math.round(meta.width * 0.78);
    const h = Math.round(meta.height * 0.78);
    const buffer = await sharp(file).extract({ left: Math.round(meta.width * 0.14), top: Math.round(meta.height * 0.08), width: w, height: h })
      .flop().resize(320).modulate({ brightness: 1.08, saturation: 0.9 }).jpeg({ quality: 70 }).toBuffer();
    let r;
    try {
      r = await visual.visualSearch(buffer, { limit: 6 });
    } catch (error) {
      record('visual', `${p.title}: ${error.message}`, ['visual search unavailable']);
      return;
    }
    n += 1;
    const f = [];
    const ids = r.items.map((i) => i.product.id);
    if (ids[0] === p.id) exact += 1;
    if (ids.slice(0, 3).includes(p.id)) exact3 += 1;
    const top = r.items[0]?.product;
    const family = (slug) => ({ 'womens-watches': 'watches', 'mens-watches': 'watches', tops: 'dresses', 'womens-dresses': 'dresses', 'womens-shoes': 'shoes', 'mens-shoes': 'shoes' }[slug] || slug);
    const sameFamily = (a, b) => family(a) === family(b);
    if (top && sameFamily(top.category_slug, p.category_slug)) sameCat += 1;
    if (!r.recognized) f.push(`not recognized (${r.reason}: ${r.detected?.label})`);
    else if (!top || (top.id !== p.id && !sameFamily(top.category_slug, p.category_slug))) f.push(`top result "${top?.title}" (${top?.category_slug}) is neither the product nor its category`);
    if (r.recognized && !sameFamily(r.detected?.category?.slug, p.category_slug) && top?.id !== p.id) f.push(`detected "${r.detected?.label}" instead of ${p.category_name}`);
    record('visual', `${p.title} → ${top ? top.title : '(nothing)'}${r.recognized ? ` [${r.detected.label} ${Math.round(r.detected.confidence * 100)}%]` : ''}`, f);
  }
  visualStats = { n, exact, exact3, sameCat };
};
let visualStats = null;

// ------------------------------------------------------------------------------------------------ runner + report

const FEATURES = [
  ['compare', 'Compare', auditCompare], ['bundle', 'Bundle builder', auditBundle], ['gift', 'Gift finder', auditGift],
  ['look', 'Complete the look', auditLook], ['explain', 'Spec explainer', auditExplain], ['qa', 'Product Q&A', auditQa],
  ['reviews', 'Review summary', auditReviews], ['similar', 'Similar products (recommender.js)', auditSimilar],
  ['boughtTogether', 'Bought together (recommender.js)', auditBoughtTogether], ['cart', 'Cart insights', auditCart],
  ['dna', 'Shopping DNA', auditDna], ['finder', 'Guided finder', auditFinder], ['search', 'Smart search wrapper', auditSearch],
  ['visual', 'Snap & Find', auditVisual],
];

const scorecard = (rows) => {
  const out = {};
  for (const [key] of FEATURES) {
    const mine = rows.filter((r) => r.feature === key);
    if (mine.length) out[key] = { pass: mine.filter((r) => r.pass).length, total: mine.length };
  }
  return out;
};

const pctOf = (s) => (s ? `${s.pass}/${s.total} (${Math.round((100 * s.pass) / s.total)}%)` : '—');

const writeReport = (baseline) => {
  const now = scorecard(results);
  const before = baseline ? scorecard(baseline.results) : null;
  const old = fs.existsSync(REPORT) ? fs.readFileSync(REPORT, 'utf8') : '';
  const notes = old.match(/<!-- notes:start -->[\s\S]*?<!-- notes:end -->/)?.[0] || '<!-- notes:start -->\n_No notes yet._\n<!-- notes:end -->';
  const lines = [
    '# AI feature quality audit',
    '',
    `Generated by \`npm run ai:audit\` (\`scripts/auditAiFeatures.js\`) on ${new Date().toISOString().slice(0, 10)} against the local database (${catalog.products.length} products, PKR).`,
    'Each case runs a feature in-process and applies the checks a shopper would make. Carts and shopper histories for cart insights and Shopping DNA are stubbed in memory; nothing is written to the database.',
    'Core chat search ranking is out of scope (it has its own eval: `scripts/evalRanking.js`). Similar / bought-together live in `ranking/recommender.js` and are measured here but fixed there.',
    '',
    '## Scorecard',
    '',
    `| Feature | BEFORE${baseline ? ` (${baseline.date})` : ''} | AFTER (this run) |`,
    '|---|---|---|',
    ...FEATURES.map(([key, label]) => `| ${label} | ${pctOf(before?.[key])} | ${pctOf(now[key])} |`),
    `| **Total** | ${before ? pctOf(Object.values(before).reduce((a, s) => ({ pass: a.pass + s.pass, total: a.total + s.total }), { pass: 0, total: 0 })) : '—'} | ${pctOf(Object.values(now).reduce((a, s) => ({ pass: a.pass + s.pass, total: a.total + s.total }), { pass: 0, total: 0 }))} |`,
    '',
  ];
  const vs = (s) => (s ? `${s.n} products (cropped, mirrored, recompressed thumbnails): top-1 same product ${s.exact}/${s.n}, product in top 3 ${s.exact3}/${s.n}, top-1 same category ${s.sameCat}/${s.n}` : 'not run');
  lines.push(`Snap & Find recall (men's/women's watches, tops/dresses and men's/women's shoes count as one category family) — BEFORE: ${vs(baseline?.visualStats)}. AFTER: ${vs(visualStats)}.`, '', '## Notes', '', notes, '');
  lines.push('## Failing cases — AFTER (this run)', '');
  for (const [key, label] of FEATURES) {
    const bad = results.filter((r) => r.feature === key && !r.pass);
    if (!bad.length) continue;
    lines.push(`### ${label}`, '');
    for (const r of bad) lines.push(`- ${r.name.replace(/\|/g, '/')}`, ...r.failures.map((x) => `  - ${x}`));
    lines.push('');
  }
  if (baseline) {
    lines.push('## Failing cases — BEFORE (baseline)', '');
    for (const [key, label] of FEATURES) {
      const bad = baseline.results.filter((r) => r.feature === key && !r.pass);
      if (!bad.length) continue;
      lines.push(`<details><summary>${label}: ${bad.length} failing</summary>`, '');
      for (const r of bad) lines.push(`- ${r.name.replace(/\|/g, '/')}`, ...r.failures.map((x) => `  - ${x}`));
      lines.push('', '</details>', '');
    }
  }
  fs.writeFileSync(REPORT, `${lines.join('\n')}\n`);
};

const main = async () => {
  const started = Date.now();
  if (embeddings.wanted()) await embeddings.load();
  catalog = await getCatalog();
  // the neural vectors are attached from the db; wait until the catalog is in the same mode as the live api
  for (let i = 0; i < 50 && embeddings.ready() && catalog.mode !== 'neural'; i += 1) await new Promise((r) => setTimeout(r, 200));
  console.log(`catalog: ${catalog.products.length} products, ${catalog.mode} mode`);
  for (const [key, label, fn] of FEATURES) {
    if (only && !only.has(key)) continue;
    if (key === 'visual' && flag('no-visual')) continue;
    const t0 = Date.now();
    try {
      await fn();
    } catch (error) {
      record(key, `${label} crashed`, [error.stack.split('\n').slice(0, 3).join(' ')]);
    }
    const mine = results.filter((r) => r.feature === key);
    console.log(`\n== ${label}: ${mine.filter((r) => r.pass).length}/${mine.length} (${Date.now() - t0} ms)`);
    for (const r of mine) {
      if (r.pass && !flag('verbose')) continue;
      console.log(`  ${r.pass ? 'PASS' : 'FAIL'} ${r.name}`);
      for (const x of r.failures) console.log(`       - ${x}`);
    }
  }
  if (visualStats) console.log(`\nSnap & Find: top-1 product ${visualStats.exact}/${visualStats.n}, top-3 ${visualStats.exact3}/${visualStats.n}, top-1 category ${visualStats.sameCat}/${visualStats.n}`);
  const card = scorecard(results);
  console.log('\nScorecard');
  for (const [key, label] of FEATURES) if (card[key]) console.log(`  ${label.padEnd(36)} ${pctOf(card[key])}`);
  const snapshot = { date: new Date().toISOString().slice(0, 10), results, visualStats };
  if (flag('baseline') && !only) {
    fs.mkdirSync(path.dirname(BASELINE), { recursive: true });
    fs.writeFileSync(BASELINE, JSON.stringify(snapshot, null, 1));
    console.log(`baseline saved to ${path.relative(ROOT, BASELINE)}`);
  }
  if (!flag('no-write') && !only) {
    const baseline = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, 'utf8')) : null;
    writeReport(baseline);
    console.log(`report written to ${path.relative(ROOT, REPORT)}`);
  }
  console.log(`done in ${((Date.now() - started) / 1000).toFixed(1)} s`);
};

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => db.destroy());
