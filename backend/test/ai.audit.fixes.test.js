// Regression tests for the issues found by the AI feature audit (scripts/auditAiFeatures.js, test/AI_FEATURE_AUDIT.md).
const assert = require('node:assert/strict');
const { api, db } = require('./helpers');
const models = require('../api/modules/ai/models/ai.models');
const { buildComparison, buildProsCons, headlineQuantity } = require('../api/modules/ai/engine/compare');
const { explainProduct } = require('../api/modules/ai/engine/explain');
const { goesWith, compatible, isKidsItem, isNovelty, accessoryKind } = require('../api/modules/ai/engine/complements');
const { scoreSentence } = require('../api/modules/ai/engine/reviews/sentiment');
const { summarizeReviews, labelFor } = require('../api/modules/ai/engine/reviews/summary');
const { yesNo } = require('../api/modules/ai/engine/qa');
const { PERSONAS } = require('../api/modules/ai/engine/shoppingDna');
const { getCatalog } = require('../api/modules/ai/engine/retrieval/catalog');
const { buildBundle } = require('../api/modules/ai/engine/bundle');
const { buildGift } = require('../api/modules/ai/engine/gift');
const { completeLook } = require('../api/modules/ai/engine/outfit');
const { cartInsights } = require('../api/modules/ai/engine/cartInsights');

const AI = '/api/v1/ai';
const acc = (id, title, specs = {}, extra = {}) => ({ id, title, category_slug: 'mobile-accessories', specs, stock: 5, price: 5000, tags: [], ...extra });
const phone = (id, title, brand) => ({ id, title, brand_name: brand, category_slug: 'smartphones', specs: {}, stock: 5, price: 100000, tags: ['smartphones'] });

describe('AI feature audit fixes (unit, no db)', () => {
  it('AUD-U1 compare crowns the headline figure, not expandable storage or a charging-case total', () => {
    assert.deepEqual(headlineQuantity('64 GB (microSD up to 256 GB)'), { unit: 'gb', value: 64 });
    assert.deepEqual(headlineQuantity('Up to 5 hours listening, 24 hours with charging case'), { unit: 'h', value: 5 });
    const mk = (id, specs) => ({ id, title: `P${id}`, price: 50000 + id, rating: 4, rating_count: 10, stock: 5, specs });
    const { rows } = buildComparison([mk(1, { Storage: '32 GB (microSD up to 200 GB)', Battery: 'Up to 5 hours, 24 hours with charging case' }), mk(2, { Storage: '64 GB', Battery: 'Up to 20 hours' })]);
    assert.equal(rows.find((r) => r.label === 'Storage').bestIndex, 1);
    assert.equal(rows.find((r) => r.label === 'Battery').bestIndex, 1);
  });

  it('AUD-U2 a sub-3.5★ product is never "highest rated" and "lower rating" at once', () => {
    const mk = (id, rating) => ({ id, title: `P${id}`, price: 50000 * id, rating, rating_count: 8, stock: 5, specs: {}, category_slug: 'laptops' });
    const products = [mk(1, 3.4), mk(2, 2.8)];
    const { rows } = buildComparison(products);
    const pc = buildProsCons(products, rows, products.map((p) => explainProduct(p)));
    assert.ok(!pc[0].pros.some((x) => /highest rated/i.test(x)));
    assert.ok(pc[0].cons.some((x) => /lower rating .*best of this group/i.test(x)));
  });

  it('AUD-U3 accessories must fit the device: model-specific cases, Apple-only gear, laptop add-ons', () => {
    const iphone13 = phone(1, 'iPhone 13 Pro', 'Apple');
    const s10 = phone(2, 'Samsung Galaxy S10', 'Samsung');
    const case12 = acc(10, 'iPhone 12 Silicone Case with MagSafe Plum', { Type: 'Protective phone case', Compatibility: 'iPhone 12 and iPhone 12 Pro' });
    const magsafe = acc(11, 'Apple MagSafe Battery Pack', { Type: 'Magnetic wireless power bank', Compatibility: 'iPhone 12, 13, 14 and 15 series (MagSafe)' });
    const airpods = acc(12, 'Apple Airpods', { Type: 'True wireless earbuds', Compatibility: 'iPhone, iPad, Mac' });
    const pedestal = acc(13, 'TV Studio Camera Pedestal', { Type: 'Studio camera pedestal' });
    const laptop = { id: 3, title: 'Asus Zenbook', brand_name: 'Asus', category_slug: 'laptops', specs: {}, stock: 5, price: 500000, tags: [] };
    assert.equal(compatible(iphone13, case12), false);
    assert.equal(compatible(s10, magsafe), false);
    assert.equal(compatible(iphone13, magsafe), true);
    assert.equal(compatible(s10, airpods), true); // bluetooth audio works with anything
    assert.equal(goesWith(laptop, airpods), true);
    assert.equal(goesWith(laptop, pedestal), false);
    assert.equal(goesWith(iphone13, s10), false); // another phone is a substitute, not a complement
    assert.equal(accessoryKind(magsafe), 'power');
  });

  it('AUD-U4 children\'s items and novelty props are recognised', () => {
    assert.equal(isKidsItem({ title: 'Girl Summer Dress', specs: { 'Ideal For': 'Girls, ages 4 to 10' } }), true);
    assert.equal(isKidsItem({ title: 'Gray Dress', specs: { Occasion: 'Office' } }), false);
    assert.equal(isNovelty({ title: 'Party Glasses', specs: { Use: 'Parties, costume events, photo shoots' } }), true);
    const dress = { id: 1, title: 'Gray Dress', category_slug: 'womens-dresses', gender: 'women', specs: {}, tags: [] };
    const kidsDress = { id: 2, title: 'Girl Summer Dress', category_slug: 'tops', gender: 'women', specs: { 'Ideal For': 'Girls, ages 4 to 10' }, tags: [] };
    const shoes = { id: 3, title: 'Red Shoes', category_slug: 'womens-shoes', gender: 'women', specs: {}, tags: [] };
    assert.equal(goesWith(shoes, kidsDress), false);
    assert.equal(goesWith(shoes, dress), true);
  });

  it('AUD-U5 review sentiment: negation stops at a comma, "feels cheap" and "poor value" are complaints', () => {
    assert.ok(scoreSentence('Not long-lasting, it fades within a few hours.').score < 0);
    assert.ok(scoreSentence('The bottle feels cheap for the price.').score < 0);
    assert.ok(scoreSentence('Poor value for money, there are better options at this price.').score < 0);
    assert.ok(scoreSentence('Build quality is not what I expected at this price.').score < 0);
    assert.ok(scoreSentence('The scent lasts all day, even in the heat.').score > 0);
  });

  it('AUD-U6 the review label follows the star average and pros need real praise', () => {
    assert.equal(labelFor(0.6, 3.6), 'Positive');
    assert.equal(labelFor(0.6, 4.4), 'Very positive');
    assert.equal(labelFor(0.3, 2.4), 'Negative');
    const reviews = [
      { rating: 3, comment: 'Okay for the price.' }, { rating: 3, comment: 'Okay for the price.' },
      { rating: 2, comment: 'The keyboard feels shallow and mushy.' }, { rating: 3, comment: 'Battery backup is impressive.' },
    ];
    const s = summarizeReviews(reviews, { categorySlug: 'laptops', title: 'Laptop' });
    assert.ok(!s.pros.some((p) => p.aspect === 'Value for money'));
    assert.ok(s.pros.some((p) => p.aspect === 'Battery life'));
    assert.ok(s.cons.some((p) => p.aspect === 'Keyboard'));
    assert.notEqual(s.sentiment.label, 'Very positive');
  });

  it('AUD-U7 product Q&A says "yes" only when the asked feature is really there', () => {
    const spec = (text) => ({ source: 'spec', text });
    assert.equal(yesNo('is it automatic', spec('Transmission: 6-speed manual')), 'no');
    assert.equal(yesNo('does it support wireless charging', spec('Charging: 5W wired (Lightning)')), 'no');
    assert.equal(yesNo('does it support wireless charging', spec('Charging: 20W wired, 15W MagSafe, 7.5W Qi')), 'yes');
    assert.equal(yesNo('is it real leather', spec('Material: PU faux leather with polyester lining')), 'no');
    assert.equal(yesNo('is it waterproof', spec('Water Resistance: 30 m (3 ATM, splash-proof)')), 'partly');
    assert.equal(yesNo('is it waterproof', spec('Water Resistance: IP68 (up to 6 m for 30 min)')), 'yes');
    assert.equal(yesNo('is it dishwasher safe', spec('Dishwasher Safe: Jar and lid, yes')), 'yes');
    assert.equal(yesNo('is it for men', spec('Gender: Unisex')), 'yes');
    assert.equal(yesNo('does it support 5g', spec('Connectivity: Wi-Fi, Bluetooth 5.0 (LTE optional)')), 'no');
    assert.equal(yesNo('does it have noise cancellation', spec('Noise Cancellation: None')), 'no');
  });

  it('AUD-U8 Shopping DNA: a dominant department beats "Curious Explorer"', () => {
    const t = { price: 0.4, brand: 0.2, deal: 0.1, quality: 0.3, trend: 0.3, breadth: 0.9, research: 0.3 };
    const d = { electronics: 0.67, fashion: 0.15, beauty: 0.14, home: 0.04, groceries: 0, sports: 0, automotive: 0 };
    const best = PERSONAS.map((p) => ({ title: p.title, v: p.score(t, d, { branded: 2 }) })).sort((a, b) => b.v - a.v)[0].title;
    assert.equal(best, 'The Tech Enthusiast');
    const cheap = { ...t, price: 0.75, deal: 0.3 };
    const spread = { electronics: 0.2, fashion: 0.2, beauty: 0, home: 0.3, groceries: 0.3, sports: 0, automotive: 0 };
    assert.equal(PERSONAS.map((p) => ({ title: p.title, v: p.score(cheap, spread, { branded: 2 }) })).sort((a, b) => b.v - a.v)[0].title, 'The Smart Saver');
  });
});

describe('AI feature audit fixes (integration, local catalog)', function suite() {
  this.timeout(60000);
  let catalog;
  const byTitle = (title) => catalog.products.find((p) => p.title === title);
  before(async () => {
    catalog = await getCatalog();
  });

  it('AUD-01 bundles fill roles with the real thing: RTX gaming laptop, audio for earphones, no bedside "desk"', async () => {
    const gaming = await buildBundle({ goal: 'gaming setup', budget: 800000 });
    const laptop = gaming.items.find((i) => i.role === 'Gaming laptop').product.product;
    assert.match(String(laptop.specs.Graphics), /rtx|gtx|radeon/i);
    for (const goal of ['university starter kit', 'travel kit']) {
      const b = await buildBundle({ goal, budget: 250000 });
      const ear = b.items.find((i) => i.role === 'Earphones');
      if (ear) assert.equal(accessoryKind(ear.product.product), 'audio');
      for (const it of b.items) assert.ok(!/\bcase\b/i.test(it.product.product.title), `${it.role} filled by a phone case`);
    }
    const office = await buildBundle({ goal: 'home office setup', budget: 600000 });
    assert.ok(!office.items.some((i) => /bedside/i.test(i.product.product.title)));
    if (office.skippedRoles.includes('Desk / table')) assert.match(office.explanation, /don't stock a suitable desk/i);
  });

  it('AUD-02 a party outfit for women is an adult, dressy outfit', async () => {
    const b = await buildBundle({ goal: 'party outfit for women', budget: 80000 });
    for (const it of b.items) {
      assert.ok(!isKidsItem(it.product.product), `${it.product.product.title} is a children's item`);
      assert.ok(!isNovelty(it.product.product));
    }
    const outfit = b.items.find((i) => i.role === 'Outfit').product.product;
    assert.match(`${outfit.specs.Occasion} ${outfit.specs.Style || ''}`, /part|wedding|evening|formal|gala|festive/i);
  });

  it('AUD-03 gifts: a child gets children\'s things, an unknown-gender boss gets neutral gifts, no cases or props', async () => {
    const kid = await buildGift({ recipient: 'daughter', age: 8, budget: { min: null, max: 10000 }, limit: 8 });
    assert.ok(kid.items.length >= 4);
    assert.ok(kid.items.some((i) => isKidsItem(i.product)), 'the girls\' dress should be suggested');
    for (const i of kid.items) assert.ok(!['camera', 'case', 'charger', 'power', 'studio'].includes(accessoryKind(i.product)), `${i.product.title} for an 8-year-old`);
    const boss = await buildGift({ recipient: 'my boss', occasion: 'office', budget: { min: null, max: 40000 }, limit: 8 });
    assert.ok(boss.items.slice(0, 4).filter((i) => i.product.gender === 'women' || i.product.gender === 'men').length <= 1);
    const all = [kid, boss, await buildGift({ recipient: 'colleague', occasion: 'farewell', budget: { min: null, max: 10000 }, limit: 8 })];
    for (const r of all) for (const i of r.items) assert.ok(!/\bcase\b|charger|pedestal/i.test(i.product.title) && !isNovelty(i.product), i.product.title);
  });

  it('AUD-04 complete the look: a child\'s dress gets no watch, fragrance or heels; a phone gets compatible accessories', async () => {
    const kids = byTitle('Girl Summer Dress');
    const look = await completeLook(kids.id);
    for (const l of look.look) {
      assert.ok(!['womens-watches', 'fragrances', 'womens-jewellery'].includes(l.category.slug), l.item.product.title);
      assert.ok(!l.item.product.specs?.['Heel Height'], l.item.product.title);
    }
    const iphone = byTitle('iPhone 13 Pro');
    const goes = await completeLook(iphone.id);
    assert.equal(goes.kind, 'complementary');
    for (const i of goes.items) {
      assert.equal(i.product.category_slug, 'mobile-accessories');
      assert.ok(compatible(iphone, i.product), `${i.product.title} does not fit an iPhone 13 Pro`);
    }
    const sunglasses = byTitle('Black Sun Glasses');
    const mixed = await completeLook(sunglasses.id);
    const genders = new Set(mixed.look.map((l) => l.item.product.gender).filter((g) => g === 'men' || g === 'women'));
    assert.ok(genders.size <= 1, 'a look should not mix men\'s and women\'s pieces');
  });

  it('AUD-05 cart insights: coupon-aware free-shipping gap, no substitutes or incompatible add-ons', async () => {
    const original = models.cartSnapshot;
    try {
      const lunch = byTitle('Lunch Box');
      const tray = byTitle('Ice Cube Tray');
      models.cartSnapshot = async () => ({ items: [{ ...lunch, quantity: 1 }, { ...tray, quantity: 1 }], couponCode: 'FLAT500' });
      const coupon = await db('coupons').where({ code: 'FLAT500' }).first();
      const r = await cartInsights(-1);
      const subtotal = lunch.price + tray.price;
      if (coupon && coupon.is_active && subtotal >= Number(coupon.min_order_amount) && subtotal - Number(coupon.value) < 5000) {
        assert.equal(r.freeShippingGap.remaining, 5000 - (subtotal - Number(coupon.value)));
      }
      const s10 = byTitle('Samsung Galaxy S10');
      const case12 = byTitle('iPhone 12 Silicone Case with MagSafe Plum');
      models.cartSnapshot = async () => ({ items: [{ ...s10, quantity: 1 }, { ...case12, quantity: 1 }], couponCode: null });
      const r2 = await cartInsights(-1);
      for (const x of r2.completeTheSet) {
        assert.notEqual(x.product.category_slug, 'smartphones');
        assert.ok(compatible(s10, x.product), `${x.product.title} does not work with a Galaxy S10`);
      }
    } finally {
      models.cartSnapshot = original;
    }
  });

  it('AUD-06 product Q&A over the API: honest no, use-case verdicts and cited catalog facts', async () => {
    const ask = async (title, question) => (await api.post(`${AI}/products/${byTitle(title).id}/ask`).send({ question }).expect(200)).body.data;
    assert.match((await ask('Kawasaki Z800', 'is it automatic?')).answer, /^No\b.*manual/i);
    assert.match((await ask('iPhone 5s', 'is it good for gaming?')).answer, /not really/i);
    assert.match((await ask('Asus Zenbook Pro Dual Screen Laptop', 'is it good for gaming?')).answer, /yes/i);
    assert.match((await ask('Chanel Coco Noir Eau De', 'how long does the scent last?')).answer, /8 to 10 hours/);
    const price = await ask('Realme X', 'what is the price?');
    assert.ok(price.evidence.some((e) => /Price: Rs/.test(e.text)));
  });
});
