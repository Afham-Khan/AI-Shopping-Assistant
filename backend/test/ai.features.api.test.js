const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { api, db, registerUser } = require('./helpers');

const AI = '/api/v1/ai';
let n = 0;
const aiUser = () => {
  n += 1;
  return registerUser({ email: `test+aif${Date.now()}${n}@cartwise.test` });
};

const dbReady = async () => {
  try {
    return Number((await db('products').count('* as c').first()).c) > 0;
  } catch {
    return false;
  }
};

describe('AI phase 2 API (integration)', function features() {
  this.timeout(120000);
  let session;

  before(async function setup() {
    if (!(await dbReady())) return this.skip();
    session = await aiUser();
    return null;
  });

  describe('bundle builder', () => {
    it('BND-01 builds a gaming setup within budget', async () => {
      const res = await api.post(`${AI}/bundle`).send({ goal: 'build me a gaming setup', budget: 700000 }).expect(200);
      const b = res.body.data;
      assert.equal(b.template, 'gaming_setup');
      assert.ok(b.total <= 700000);
      assert.equal(b.remaining, 700000 - b.total);
      assert.ok(b.items.length >= 2);
      assert.ok(b.items.some((i) => i.role === 'Gaming laptop' && i.product.category.slug === 'laptops'));
      const ids = b.items.map((i) => i.product.id);
      assert.equal(new Set(ids).size, ids.length);
      b.items.forEach((i) => {
        assert.ok(i.product.match.reasons.length);
        assert.ok(Array.isArray(i.alternatives) && i.alternatives.length <= 2);
      });
      assert.ok(b.explanation.length > 40);
      assert.ok(Array.isArray(b.savingsTips));
    });

    it('BND-02 keeps the most important role when the budget is tight', async () => {
      const res = await api.post(`${AI}/bundle`).send({ goal: 'home office setup', budget: 400000 }).expect(200);
      assert.ok(res.body.data.items.some((i) => i.role === 'Laptop'));
      assert.ok(res.body.data.total <= 400000);
    });

    it('BND-03 validates and rejects unknown goals', async () => {
      await api.post(`${AI}/bundle`).send({ goal: 'gym', budget: 10 }).expect(400);
      await api.post(`${AI}/bundle`).send({ goal: 'qwzx plorp', budget: 5000 }).expect(400);
    });

    it('BND-04 chat: bundle intent with budget clarification', async () => {
      const first = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'build me a gym starter pack' }).expect(200);
      const m1 = first.body.data.message.meta;
      assert.equal(m1.intent, 'bundle');
      assert.ok(m1.clarify);
      const second = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'Rs 50,000', conversationId: first.body.data.conversationId }).expect(200);
      const m2 = second.body.data.message.meta;
      assert.equal(m2.intent, 'bundle');
      assert.ok(m2.bundle && m2.bundle.total <= 50000);
      assert.ok(m2.actions.some((a) => a.type === 'add_bundle_to_cart' && a.productIds.length === m2.bundle.items.length));
    });
  });

  describe('grounded product q&a', () => {
    let phone;
    before(async () => {
      phone = await db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', 'smartphones')
        .whereRaw("jsonb_exists(p.specs, 'RAM')").first('p.id', 'p.specs', 'p.title');
    });

    it('QA-01 numeric spec lookup cites the spec', async () => {
      const res = await api.post(`${AI}/products/${phone.id}/ask`).send({ question: 'How much RAM does it have?' }).expect(200);
      const d = res.body.data;
      assert.ok(d.answer.includes(phone.specs.RAM));
      assert.ok(d.confidence >= 0.6);
      assert.ok(d.evidence.some((e) => e.source === 'spec'));
      assert.ok(d.followUps.length > 0);
    });

    it('QA-02 honest fallback when the answer is not in the data', async () => {
      const res = await api.post(`${AI}/products/${phone.id}/ask`).send({ question: 'can it fly to the moon?' }).expect(200);
      assert.match(res.body.data.answer, /couldn't find that/);
      assert.ok(res.body.data.confidence < 0.4);
    });

    it('QA-03 price and stock come from catalog facts', async () => {
      const res = await api.post(`${AI}/products/${phone.id}/ask`).send({ question: 'is it in stock?' }).expect(200);
      assert.match(res.body.data.answer, /in stock|out of stock/);
      await api.post(`${AI}/products/99999999/ask`).send({ question: 'price?' }).expect(404);
      await api.post(`${AI}/products/${phone.id}/ask`).send({}).expect(400);
    });

    it('QA-04 chat routes ordinal questions to q&a', async () => {
      const first = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'smartphones under 150k' }).expect(200);
      const shown = first.body.data.message.meta.products;
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'does the second one have a good camera?', conversationId: first.body.data.conversationId }).expect(200);
      const { meta } = res.body.data.message;
      assert.equal(meta.intent, 'product_question');
      assert.equal(meta.products[0].id, shown[1].id);
      assert.ok(meta.qa && typeof meta.qa.confidence === 'number');
    });
  });

  describe('cart insights and shopping dna', () => {
    it('CIN-01 requires auth', async () => {
      await api.get(`${AI}/cart-insights`).expect(401);
      await api.get(`${AI}/profile`).expect(401);
    });

    it('CIN-02 empty cart', async () => {
      const res = await api.get(`${AI}/cart-insights`).set(session.auth).expect(200);
      assert.deepEqual(res.body.data.savings, []);
      assert.equal(res.body.data.freeShippingGap, null);
    });

    it('CIN-03 small cart: free-shipping gap, savings and complete-the-set', async () => {
      const user = await aiUser();
      const cheap = await db('products').where('stock', '>', 5).whereBetween('price', [1000, 2500]).orderBy('id').first('id', 'price');
      const pricey = await db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', 'smartphones')
        .where('p.stock', '>', 5).orderBy('p.price', 'desc').first('p.id');
      await api.post('/api/v1/cart/items').set(user.auth).send({ productId: cheap.id, quantity: 1 }).expect(200);
      let res = await api.get(`${AI}/cart-insights`).set(user.auth).expect(200);
      assert.equal(res.body.data.freeShippingGap.remaining, 5000 - cheap.price);
      assert.ok(res.body.data.freeShippingGap.suggestions.every((p) => p.price >= 5000 - cheap.price));
      await api.post('/api/v1/cart/items').set(user.auth).send({ productId: pricey.id, quantity: 1 }).expect(200);
      res = await api.get(`${AI}/cart-insights`).set(user.auth).expect(200);
      const d = res.body.data;
      assert.equal(d.freeShippingGap, null);
      assert.ok(d.completeTheSet.length > 0);
      const prices = new Map([[cheap.id, cheap.price], [pricey.id, (await db('products').where({ id: pricey.id }).first('price')).price]]);
      d.savings.forEach((s) => {
        assert.ok(s.save > 0);
        assert.ok(s.alternative.price < prices.get(s.productId));
        assert.notEqual(s.alternative.id, s.productId);
      });
      assert.match(d.summary, /cart has 2 items/);
    });

    it('DNA-01 new users get the starter persona with preferences', async () => {
      const user = await aiUser();
      await api.put('/api/v1/users/me/preferences').set(user.auth).send({ interests: ['fragrances'], gender: 'women' }).expect(200);
      const res = await api.get(`${AI}/profile`).set(user.auth).expect(200);
      assert.equal(res.body.data.persona.title, 'The Fresh Explorer');
      assert.match(res.body.data.persona.description, /Fragrances/);
      assert.ok(res.body.data.traits.length >= 5);
    });

    it('DNA-02 active users get traits, persona and explanations', async () => {
      const user = await aiUser();
      const laptops = await db('products as p').join('categories as c', 'c.id', 'p.category_id').whereIn('c.slug', ['laptops', 'smartphones']).limit(4).select('p.id');
      for (const p of laptops) await api.post('/api/v1/wishlist').set(user.auth).send({ productId: p.id }).expect((r) => assert.ok(r.status < 300));
      for (const p of laptops) await api.post('/api/v1/interactions').set(user.auth).send({ productId: p.id, type: 'view' });
      const res = await api.get(`${AI}/profile`).set(user.auth).expect(200);
      const d = res.body.data;
      assert.equal(d.persona.title, 'The Tech Enthusiast');
      d.traits.forEach((t) => assert.ok(t.value >= 0 && t.value <= 1 && t.description));
      assert.ok(d.topCategories[0].share > 0);
      assert.ok(d.signals.wishlist >= 4);
      assert.ok(d.howWeUseIt.length >= 2);
    });
  });

  describe('visual search', () => {
    let product;
    let image;
    before(async () => {
      product = await db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', 'smartphones').orderBy('p.id').first('p.id', 'p.thumbnail_url');
      const file = path.join(__dirname, '..', product.thumbnail_url || '');
      image = fs.existsSync(file) ? fs.readFileSync(file) : null;
    });

    it('VIS-01 finds the photographed product and detects its category', async function vis01() {
      if (!image) return this.skip();
      const res = await api.post(`${AI}/visual-search?limit=6`).attach('image', image, { filename: 'p.webp', contentType: 'image/webp' });
      if (res.status === 503) return this.skip();
      assert.equal(res.status, 200);
      const d = res.body.data;
      assert.ok(d.products.slice(0, 3).some((p) => p.id === product.id));
      assert.equal(d.detected.category.slug, 'smartphones');
      assert.ok(d.detected.confidence > 0 && d.detected.confidence <= 1);
      assert.equal(typeof d.latencyMs, 'number');
      return null;
    });

    it('VIS-02 text-to-image search', async function vis02() {
      const res = await api.get(`${AI}/visual-search/text`).query({ q: 'red sneakers' });
      if (res.status === 503) return this.skip();
      assert.equal(res.status, 200);
      assert.ok(res.body.data.products.slice(0, 5).some((p) => /shoe|sneaker|jordan|trainer/i.test(p.title)));
      return null;
    });

    it('VIS-03 rejects non-images and missing files', async () => {
      await api.post(`${AI}/visual-search`).attach('image', Buffer.from('hello'), { filename: 'a.txt', contentType: 'text/plain' }).expect(400);
      await api.post(`${AI}/visual-search`).expect(400);
    });

    it('VIS-04 insights report the visual model', async () => {
      const res = await api.get(`${AI}/insights`).expect(200);
      assert.ok('enabled' in res.body.data.visual);
      assert.equal(typeof res.body.data.visual.indexedImages, 'number');
    });
  });
});
