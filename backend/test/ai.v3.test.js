const assert = require('node:assert/strict');
const { explainSpec, explainProduct } = require('../api/modules/ai/engine/explain');
const { colorHarmony, parseColor } = require('../api/modules/ai/engine/outfit');
const { cleanSpeech } = require('../api/modules/ai/engine/nlu/speech');
const { analyze } = require('../api/modules/ai/engine/nlu');
const { createGuard, TokenBucket, LruCache, CircuitBreaker } = require('../api/modules/ai/engine/llm/guard');
const llm = require('../api/modules/ai/engine/llm');
const { buildComparison, buildProsCons, parseNeed, pickForNeed } = require('../api/modules/ai/engine/compare');
const { mapInterests, normRecipient, ageBandOf } = require('../api/modules/ai/engine/gift');
const { buildProfile, aversion } = require('../api/modules/ai/engine/ranking/personalization');

const ctx = (kind) => ({ kind, p: { title: 'x', brand_name: null } });

describe('AI v3 — unit', () => {
  describe('spec explainer (rules)', () => {
    it('EXP-U1 laptop RAM: 16 GB is level 4 and mentions programming', () => {
      const e = explainSpec('RAM', '16 GB DDR4', ctx('laptop'));
      assert.equal(e.level, 4);
      assert.match(e.title, /16 GB RAM/);
      assert.match(e.meaning, /programming/);
    });
    it('EXP-U2 phone RAM thresholds differ from laptops', () => {
      assert.equal(explainSpec('RAM', '8 GB', ctx('phone')).level, 4);
      assert.equal(explainSpec('RAM', '8 GB', ctx('laptop')).level, 3);
      assert.equal(explainSpec('RAM', '1 GB', ctx('phone')).level, 1);
    });
    it('EXP-U3 storage: capacity with photo estimate; food storage gets plain advice without a level', () => {
      const s = explainSpec('Storage', '128 GB (microSD up to 1 TB)', ctx('phone'));
      assert.equal(s.level, 3);
      assert.match(s.meaning, /photos/);
      assert.match(s.meaning, /memory card/);
      const food = explainSpec('Storage', 'Refrigerate at 0 to 4 C', ctx('grocery'));
      assert.equal(food.level, null);
      assert.match(food.title, /fridge/i);
    });
    it('EXP-U4 processors map to tiers (A15 = 5, Helio G35 = 1, 8th-gen i7 is downgraded)', () => {
      assert.equal(explainSpec('Processor', 'Apple A15 Bionic (5 nm)', ctx('phone')).level, 5);
      assert.equal(explainSpec('Processor', 'MediaTek Helio G35 octa-core', ctx('phone')).level, 1);
      const old = explainSpec('Processor', 'Intel Core i7-8550U (8th Gen)', ctx('laptop'));
      assert.equal(old.level, 3);
      assert.match(old.meaning, /older generation/);
      assert.equal(explainSpec('Processor', 'Intel Core i7-1165G7 (11th Gen)', ctx('laptop')).level, 4);
    });
    it('EXP-U5 display: OLED + 120 Hz is excellent; HD+ IPS is weaker', () => {
      const d = explainSpec('Display', '6.1-inch Super Retina XDR OLED, 2532 x 1170, 120 Hz ProMotion', ctx('phone'));
      assert.equal(d.level, 5);
      assert.match(d.meaning, /120 Hz/);
      assert.ok(explainSpec('Display', '6.56-inch HD+ IPS LCD, 1612 x 720, 90 Hz', ctx('phone')).level <= 3);
    });
    it('EXP-U6 battery, charging, camera, network', () => {
      assert.equal(explainSpec('Battery', '5000 mAh', ctx('phone')).level, 5);
      assert.equal(explainSpec('Battery Life', 'Up to 17 hours video playback', ctx('laptop')).level, 5);
      assert.equal(explainSpec('Charging', '50W Flash Charge', ctx('phone')).level, 5);
      assert.match(explainSpec('Charging', '15W fast wired, Qi wireless', ctx('phone')).meaning, /wireless/);
      const cam = explainSpec('Rear Camera', 'Triple 12 MP: wide f/1.5 + ultra-wide f/1.8 + 3x telephoto f/2.8', ctx('phone'));
      assert.ok(cam.level >= 4);
      assert.match(cam.meaning, /optical zoom/);
      assert.equal(explainSpec('Network', '5G, dual SIM', ctx('phone')).level, 5);
    });
    it('EXP-U7 water resistance: IP68, watch depths', () => {
      assert.equal(explainSpec('Water Resistance', 'IP68 (up to 6 m for 30 min)', ctx('phone')).level, 5);
      assert.match(explainSpec('Water Resistance', '100 m (10 bar)', ctx('watch')).meaning, /swimming/);
      assert.equal(explainSpec('Water Resistance', '30 m (3 ATM, splash-proof)', ctx('watch')).level, 2);
    });
    it('EXP-U8 fashion and fragrance knowledge: fabric, EDP/EDT, movement, crystal', () => {
      assert.equal(explainSpec('Fabric', '100% cotton', ctx('apparel')).level, 5);
      assert.match(explainSpec('Fabric', 'Wool-blend suiting', ctx('apparel')).meaning, /winter/);
      const edp = explainSpec('Concentration', 'Eau de Parfum (EDP)', ctx('fragrance'));
      assert.equal(edp.level, 4);
      assert.match(edp.meaning, /6 to 8 hours/);
      assert.equal(explainSpec('Concentration', 'Eau de Toilette (EDT)', ctx('fragrance')).level, 3);
      assert.equal(explainSpec('Movement', 'Automatic mechanical, Rolex calibre 3235', ctx('watch')).level, 5);
      assert.equal(explainSpec('Crystal', 'Scratch-resistant sapphire', ctx('watch')).level, 5);
      assert.equal(explainSpec('OS', 'Windows 10 Home', ctx('laptop')).level, 2);
    });
    it('EXP-U9 product summary names who it is for and a weak spot', () => {
      const p = {
        id: 1, title: 'Budget Phone', category_slug: 'smartphones', category_name: 'Smartphones', price: 30000, brand_name: 'X',
        specs: { Processor: 'Unisoc T616 octa-core', RAM: '4 GB', Battery: '5000 mAh', Display: '6.6-inch FHD+ IPS LCD, 2408 x 1080' },
      };
      const x = explainProduct(p);
      assert.equal(x.product.kind, 'phone');
      assert.ok(x.specs.length >= 4);
      assert.ok(x.whoFor.length >= 1);
      assert.match(x.summary, /Keep in mind/);
      x.specs.forEach((s) => assert.ok(s.level === null || (s.level >= 1 && s.level <= 5)));
    });
    it('EXP-U10 unknown spec keys are listed as others, never guessed', () => {
      const x = explainProduct({ id: 2, title: 'Pan', category_slug: 'kitchen-accessories', specs: { 'Mystery Spec': 'abc' } });
      assert.deepEqual(x.others, [{ key: 'Mystery Spec', value: 'abc' }]);
      assert.equal(x.overall, null);
    });
  });

  describe('outfit colour harmony', () => {
    const c = (color) => parseColor({ color, specs: {} });
    it('OUT-U1 neutrals pair with everything, clashes score low', () => {
      assert.ok(colorHarmony(c('Red'), c('Black')).score >= 0.85);
      assert.equal(colorHarmony(c('Black'), c('White')).rule, 'neutral');
      assert.equal(colorHarmony(c('Red'), c('Green')).rule, 'complementary');
      assert.equal(colorHarmony(c('Red'), c('Orange')).rule, 'analogous');
      assert.ok(colorHarmony(c('Green'), c('Purple')).score < colorHarmony(c('Green'), c('Black')).score);
    });
    it('OUT-U2 parses compound colours ("Rose Gold", "Red and black")', () => {
      assert.equal(c('Rose Gold').primary.family, 'metal');
      assert.equal(parseColor({ color: null, specs: { Colour: 'Red and black' } }).primary.hue, 0);
      assert.equal(parseColor({ color: null, specs: {} }), null);
    });
  });

  describe('voice transcripts (normalizer)', () => {
    it('VOI-U1 spoken numbers become digits', () => {
      assert.equal(cleanSpeech('under fifty thousand'), 'under 50000');
      assert.equal(cleanSpeech('one lakh fifty thousand rupees'), '150000 rupees');
      assert.equal(cleanSpeech('derh lakh tak'), '150000 tak');
      assert.equal(cleanSpeech('pachas hazar se kam'), '50000 se kam');
      assert.equal(cleanSpeech('between twenty and forty thousand'), 'between 20000 and 40000');
      assert.equal(cleanSpeech('twenty five k'), '25000');
    });
    it('VOI-U2 number words without a scale are left alone ("the first one", "do you have")', () => {
      assert.equal(cleanSpeech('the first one'), 'the first one');
      assert.equal(cleanSpeech('do you have earbuds'), 'do you have earbuds');
      assert.equal(cleanSpeech('gaming setup bana do 4 lakh mein'), 'gaming setup bana do 400000 mein');
    });
    it('VOI-U3 fillers and stutters are removed, recipients are kept', () => {
      assert.equal(cleanSpeech('umm acha yaar mujhe phone chahiye'), 'mujhe phone chahiye');
      assert.equal(cleanSpeech('show me phones phones'), 'show me phones');
      assert.equal(cleanSpeech('phone dikhao na'), 'phone dikhao');
      assert.equal(cleanSpeech('bhai ke liye perfume'), 'bhai ke liye perfume');
      assert.equal(cleanSpeech('gift for my bro'), 'gift for my bro');
      assert.equal(cleanSpeech('acha laptop batao'), 'acha laptop batao');
      assert.equal(cleanSpeech('hmm'), 'hmm');
    });
    it('VOI-U4 full NLU on a punctuation-less Roman-Urdu transcript', () => {
      const a = analyze('umm acha yaar mujhe sasta phone chahiye fifty thousand tak');
      assert.equal(a.entities.category, 'smartphones');
      assert.equal(a.entities.budget.max, 50000);
      assert.equal(a.entities.recipient, null);
      assert.ok(['product_search', 'budget_query', 'recommendation'].includes(a.intent));
      assert.equal(analyze('yaar ke liye gift chahiye').entities.recipient, 'friend');
    });
  });

  describe('llm usage guard', () => {
    it('LLM-U1 token bucket allows the burst then refills over time', () => {
      let t = 0;
      const b = new TokenBucket({ capacity: 2, perMinute: 2, now: () => t });
      assert.equal(b.take(), true);
      assert.equal(b.take(), true);
      assert.equal(b.take(), false);
      t += 30000;
      assert.equal(b.take(), true);
    });
    it('LLM-U2 lru cache evicts the least recently used and expires by ttl', () => {
      let t = 0;
      const c = new LruCache({ size: 2, ttlMs: 1000, now: () => t });
      c.set('a', 1);
      c.set('b', 2);
      c.get('a');
      c.set('c', 3);
      assert.equal(c.get('b'), undefined);
      assert.equal(c.get('a'), 1);
      t += 2000;
      assert.equal(c.get('a'), undefined);
    });
    it('LLM-U3 circuit opens after 3 failures and half-opens after the cooldown', () => {
      let t = 0;
      const br = new CircuitBreaker({ threshold: 3, cooldownMs: 300000, now: () => t });
      br.failure();
      br.failure();
      assert.equal(br.allow(), true);
      br.failure();
      assert.equal(br.state, 'open');
      assert.equal(br.allow(), false);
      t += 300000;
      assert.equal(br.state, 'half-open');
      br.success();
      assert.equal(br.state, 'closed');
    });
    it('LLM-U4 guard: cache hits skip the call, daily cap and breaker refuse', async () => {
      let t = 0;
      const g = createGuard({ now: () => t, perMinute: 100, dailyLimit: 3, breakerThreshold: 3, breakerCooldownMs: 300000 });
      let calls = 0;
      const ok = async () => { calls += 1; return 'hi'; };
      assert.equal((await g.run(['p1'], ok)).from, 'llm');
      assert.equal((await g.run(['p1'], ok)).from, 'cache');
      assert.equal(calls, 1);
      assert.equal(g.info().cacheHits, 1);
      await g.run(['p2'], ok);
      await g.run(['p3'], ok);
      assert.equal((await g.run(['p4'], ok)).skipped, 'daily_limit');
      assert.equal(g.info().usedToday, 3);
      t += 86400000;
      const fail = async () => { throw new Error('quota'); };
      for (let i = 0; i < 3; i += 1) await assert.rejects(g.run([`f${i}`], fail));
      assert.equal((await g.run(['f9'], ok)).skipped, 'circuit_open');
      assert.equal(g.info().circuit, 'open');
    });
    it('LLM-U5 enhance with a fake provider: identical prompts are served from cache, failures fall back to the draft', async () => {
      llm.resetGuard({ perMinute: 100, dailyLimit: 100 });
      let calls = 0;
      const provider = { name: 'fake', model: () => 'm', complete: async () => { calls += 1; return 'Here is **Phone X** at **Rs 1,000**, a lovely pick for you.'; } };
      const payload = { query: 'phone', draft: 'Showing **Phone X** at **Rs 1,000**.', intent: 'product_search', products: [] };
      const a = await llm.enhance(payload, { provider });
      const b = await llm.enhance(payload, { provider });
      assert.equal(a.source, 'fake');
      assert.equal(b.cached, true);
      assert.equal(calls, 1);
      const broken = { name: 'broken', model: () => 'm', complete: async () => { throw new Error('down'); } };
      assert.equal((await llm.enhance({ ...payload, query: 'other' }, { provider: broken })).content, payload.draft);
      llm.resetGuard();
    });
  });

  describe('compare v2 (pure)', () => {
    const mk = (id, price, rating, specs) => ({ id, title: `P${id}`, price, rating, rating_count: 10, stock: 5, specs, category_slug: 'laptops', _bayes: rating, _quality: (rating - 2.5) / 2.5 });
    const products = [
      mk(1, 300000, 4.2, { RAM: '8 GB', Processor: 'Intel Core i5-1135G7', Graphics: 'Intel UHD Graphics 620', Weight: '1.1 kg' }),
      mk(2, 450000, 4.4, { RAM: '16 GB', Processor: 'Intel Core i7-9750H (6-core)', Graphics: 'NVIDIA GeForce RTX 2060 6 GB', Weight: '2.5 kg' }),
    ];
    const { rows } = buildComparison(products);
    const explanations = products.map((p) => explainProduct(p));
    it('CMP2-U1 rows flag differences', () => {
      assert.equal(rows.find((r) => r.label === 'Price').differs, true);
      assert.equal(rows.find((r) => r.label === 'Availability').differs, false);
    });
    it('CMP2-U2 pros/cons per product from specs and price', () => {
      const pc = buildProsCons(products, rows, explanations, [{ pros: [{ aspect: 'Battery life' }], cons: [] }, null]);
      assert.equal(pc.length, 2);
      assert.ok(pc[0].pros.some((x) => /Cheapest/.test(x)));
      assert.ok(pc[1].cons.some((x) => /Most expensive/.test(x)));
      assert.ok(pc[0].pros.some((x) => /Reviewers praise/.test(x)));
      pc.forEach((x) => assert.ok(x.pros.length <= 4 && x.cons.length <= 4));
    });
    it('CMP2-U3 "for gaming" picks the RTX laptop; "for my mom" favours value', () => {
      const gaming = pickForNeed(products, explanations, parseNeed('for gaming', analyze));
      assert.equal(gaming.productId, 2);
      assert.equal(gaming.matched, true);
      assert.match(gaming.reason, /gaming/);
      const mom = parseNeed('for my mom', analyze);
      assert.match(mom.label, /mom/);
      assert.ok(mom.value > 0.3);
      const vague = pickForNeed(products, explanations, parseNeed('qwerty zzz', analyze));
      assert.equal(vague.matched, false);
    });
  });

  describe('gift finder (pure parts)', () => {
    it('GFT-U1 recipients normalise (roman urdu too) and get an age band', () => {
      assert.equal(normRecipient('My Sister'), 'sister');
      assert.equal(normRecipient('ammi'), 'mom');
      assert.equal(ageBandOf('grandma'), 'senior');
      assert.equal(ageBandOf('sister', 9), 'kid');
    });
    it('GFT-U2 interests map to gendered categories; "surprise me" is ignored', () => {
      const m = mapInterests(['makeup', 'watches', 'surprise me'], 'women');
      assert.deepEqual(m.map((x) => x.categories), [['beauty'], ['womens-watches']]);
      assert.deepEqual(mapInterests(['watches'], 'men')[0].categories, ['mens-watches']);
    });
  });

  describe('pass is a negative signal', () => {
    it('NEG-U1 passes build category aversion and exclude the passed items', () => {
      const products = [
        { id: 1, category_slug: 'groceries', brand_name: null, price: 100 },
        { id: 2, category_slug: 'groceries', brand_name: null, price: 120 },
        { id: 3, category_slug: 'fragrances', brand_name: 'A', price: 5000 },
      ];
      const catalog = { byId: new Map(products.map((p) => [p.id, p])), vectorOf: () => null };
      const now = new Date();
      const profile = buildProfile({
        user: { id: 1, name: 'T', preferences: {} },
        interactions: [{ product_id: 1, type: 'pass', created_at: now }, { product_id: 2, type: 'pass', created_at: now }, { product_id: 3, type: 'like', created_at: now }],
        wishlist: [], cart: [], purchases: [],
      }, catalog);
      assert.ok(profile.passed.has(1));
      assert.ok(profile.catPass.get('groceries') > 0);
      assert.equal(aversion(products[0], profile, catalog), 1);
      assert.ok(aversion({ id: 9, category_slug: 'groceries' }, profile, catalog) > aversion({ id: 8, category_slug: 'fragrances' }, profile, catalog));
      assert.ok(profile.catAff.get('fragrances') > 0);
      assert.equal(profile.catAff.has('groceries'), false);
    });
  });
});
