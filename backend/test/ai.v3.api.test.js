const assert = require('node:assert/strict');
const { api, db, registerUser } = require('./helpers');

const AI = '/api/v1/ai';
const productIn = (slug, extra = (q) => q) =>
  extra(db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', slug).where('p.stock', '>', 0)).orderBy('p.id').first('p.*');

describe('AI v3 — API (integration)', function suite() {
  this.timeout(120000);
  let session;
  const chat = async (message, conversationId) => {
    const res = await api.post(`${AI}/chat`).set(session.auth).send({ message, conversationId }).expect(200);
    return res.body.data;
  };

  before(async () => {
    session = await registerUser();
  });

  describe('complete the look', () => {
    it('LOOK-01 a dress gets shoes, bag, jewellery... with gender-matched items and reasons', async () => {
      const dress = await productIn('womens-dresses');
      const res = await api.get(`${AI}/complete-look/${dress.id}`).expect(200);
      const d = res.body.data;
      assert.equal(d.kind, 'outfit');
      assert.equal(d.base.id, dress.id);
      assert.ok(d.look.length >= 3);
      const roles = d.look.map((l) => l.role);
      assert.ok(roles.includes('Shoes') && roles.includes('Bag'));
      for (const l of d.look) {
        assert.ok(!l.product.category.slug.startsWith('mens-'));
        assert.notEqual(l.product.category.slug, 'womens-dresses');
        assert.ok(l.product.match.reasons.length >= 1);
        assert.ok(l.alternatives.length <= 2);
      }
      assert.ok(d.products.length >= d.look.length);
      assert.ok(d.palette === null || typeof d.palette.tip === 'string');
    });

    it('LOOK-02 a men\'s shirt never gets women\'s items', async () => {
      const shirt = await productIn('mens-shirts');
      const res = await api.get(`${AI}/complete-look/${shirt.id}`).expect(200);
      res.body.data.products.forEach((p) => assert.ok(!p.category.slug.startsWith('womens-') && p.category.slug !== 'tops'));
    });

    it('LOOK-03 non-fashion falls back to complementary items; validation and 404', async () => {
      const phone = await productIn('smartphones');
      const res = await api.get(`${AI}/complete-look/${phone.id}?limit=4`).expect(200);
      assert.equal(res.body.data.kind, 'complementary');
      assert.ok(res.body.data.products.length <= 4);
      await api.get(`${AI}/complete-look/abc`).expect(400);
      await api.get(`${AI}/complete-look/99999999`).expect(404);
    });
  });

  describe('spec explainer', () => {
    it('EXP-01 explains every known spec with a level and a "who it\'s for" summary', async () => {
      const laptop = await productIn('laptops', (q) => q.whereRaw("p.specs->>'RAM' ilike '16%'"));
      const res = await api.get(`${AI}/explain/${laptop.id}`).expect(200);
      const d = res.body.data;
      assert.equal(d.product.kind, 'laptop');
      const ram = d.specs.find((s) => s.key === 'RAM');
      assert.equal(ram.level, 4);
      assert.match(ram.meaning, /programming/);
      assert.ok(d.summary.split('. ').length >= 2);
      d.specs.forEach((s) => {
        assert.ok(s.title && s.meaning);
        if (s.level !== null) assert.ok(s.level >= 1 && s.level <= 5 && s.levelLabel && s.scale);
      });
      assert.ok(Array.isArray(d.others));
    });

    it('EXP-02 fragrance concentration is explained', async () => {
      const perfume = await productIn('fragrances', (q) => q.whereRaw("p.specs->>'Concentration' is not null"));
      const d = (await api.get(`${AI}/explain/${perfume.id}`).expect(200)).body.data;
      assert.match(d.specs.find((s) => s.key === 'Concentration').title, /Eau de/);
      await api.get(`${AI}/explain/99999999`).expect(404);
    });

    it('EXP-03 chat: "explain the specs of the first one" uses the shown list', async () => {
      const first = await chat('show me phones');
      const shown = first.message.meta.products;
      const res = await chat('explain the specs of the first one', first.conversationId);
      const meta = res.message.meta;
      assert.equal(meta.intent, 'explain_specs');
      assert.equal(meta.explain.product.id, shown[0].id);
      assert.match(res.message.content, /plain words/);
      assert.ok(meta.explain.specs.length > 0);
    });
  });

  describe('compare v2', () => {
    let laptops;
    before(async () => {
      laptops = (await db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', 'laptops').orderBy('p.id').limit(3).select('p.id')).map((r) => r.id);
    });

    it('CMP2-01 keeps the v1 shape and adds differs, prosCons, differencesCount', async () => {
      const res = await api.post(`${AI}/compare`).send({ productIds: laptops.slice(0, 2) }).expect(200);
      const d = res.body.data;
      assert.equal(d.products.length, 2);
      assert.ok(d.verdict.summary && d.verdict.picks.length);
      d.rows.forEach((r) => assert.equal(typeof r.differs, 'boolean'));
      assert.equal(d.differencesCount, d.rows.filter((r) => r.differs).length);
      assert.equal(d.prosCons.length, 2);
      d.prosCons.forEach((x) => assert.ok(Array.isArray(x.pros) && Array.isArray(x.cons)));
      assert.equal(d.forYou, null);
    });

    it('CMP2-02 differencesOnly drops identical rows', async () => {
      const all = (await api.post(`${AI}/compare`).send({ productIds: laptops.slice(0, 2) }).expect(200)).body.data;
      const diff = (await api.post(`${AI}/compare`).send({ productIds: laptops.slice(0, 2), differencesOnly: true }).expect(200)).body.data;
      assert.ok(diff.rows.every((r) => r.differs));
      assert.equal(diff.rows.length, all.differencesCount);
    });

    it('CMP2-03 need "for gaming" returns a forYou pick with a reason', async () => {
      const d = (await api.post(`${AI}/compare`).send({ productIds: laptops, need: 'for gaming' }).expect(200)).body.data;
      assert.ok(laptops.includes(d.forYou.productId));
      assert.equal(d.forYou.matched, true);
      assert.match(d.forYou.reason, /gaming/);
      assert.equal(d.forYou.scores.length, laptops.length);
    });

    it('CMP2-04 validation', async () => {
      await api.post(`${AI}/compare`).send({ productIds: laptops, need: 'x' }).expect(400);
      await api.post(`${AI}/compare`).send({ productIds: laptops, differencesOnly: 'yes' }).expect(400);
    });

    it('CMP2-05 chat: "compare the first two for gaming" adds the for-you line', async () => {
      const first = await chat('laptops under 600k');
      const res = await chat('compare the first two for gaming', first.conversationId);
      assert.equal(res.message.meta.intent, 'compare');
      assert.ok(res.message.meta.comparison.forYou);
      assert.match(res.message.content, /For gaming/);
    });
  });

  describe('gift finder', () => {
    it('GFT-01 POST /ai/gift builds a curated, in-budget, diverse collection', async () => {
      const res = await api.post(`${AI}/gift`).send({ recipient: 'sister', occasion: 'birthday', budget: 5000, interests: ['makeup'] }).expect(200);
      const d = res.body.data;
      assert.match(d.title, /Birthday gifts for your sister/);
      assert.ok(d.products.length >= 3);
      d.products.forEach((p) => {
        assert.ok(p.price <= 5000);
        assert.ok(!p.category.slug.startsWith('mens-'));
        assert.ok(p.match.reasons.length);
      });
      assert.equal(d.products[0].category.slug, 'beauty');
      assert.equal(d.criteria.gender, 'women');
      assert.equal(d.criteria.interests[0].matched, 'makeup');
      assert.ok(d.note.length > 20);
    });

    it('GFT-02 budget as a range, kid recipient, roman-urdu recipient', async () => {
      const kid = (await api.post(`${AI}/gift`).send({ recipient: 'nephew', age: 10, budget: { min: 1000, max: 20000 } }).expect(200)).body.data;
      assert.equal(kid.criteria.ageBand, 'kid');
      kid.products.forEach((p) => assert.ok(p.price >= 1000 && p.price <= 20000));
      const ammi = (await api.post(`${AI}/gift`).send({ recipient: 'ammi', occasion: 'eid', budget: 50000 }).expect(200)).body.data;
      assert.equal(ammi.criteria.recipient, 'mom');
      assert.equal(ammi.criteria.gender, 'women');
    });

    it('GFT-03 validation', async () => {
      await api.post(`${AI}/gift`).send({}).expect(400);
      await api.post(`${AI}/gift`).send({ recipient: 'mom', budget: 10 }).expect(400);
      await api.post(`${AI}/gift`).send({ recipient: 'mom', budget: { min: 9000, max: 1000 } }).expect(400);
      await api.post(`${AI}/gift`).send({ recipient: 'mom', interests: 'makeup' }).expect(400);
    });

    it('GFT-04 chat: recipient + budget in one message -> one interest question -> collection', async () => {
      const first = await chat('birthday gift for my sister under 5000');
      const m1 = first.message.meta;
      assert.equal(m1.intent, 'gift_suggestion');
      assert.ok(m1.clarify && m1.clarify.options.includes('Surprise me'));
      assert.equal(m1.products.length, 0);
      const second = await chat('Beauty & makeup', first.conversationId);
      const m2 = second.message.meta;
      assert.equal(m2.intent, 'gift_suggestion');
      assert.equal(m2.clarify, null);
      assert.ok(m2.products.length > 0);
      m2.products.forEach((p) => assert.ok(p.price <= 5000));
      assert.ok(m2.gift && m2.gift.criteria.interests.length === 1);
    });

    it('GFT-05 chat: "surprise me" skips the interest and still curates', async () => {
      const first = await chat('anniversary gift for my wife under 50000');
      const second = await chat('Surprise me', first.conversationId);
      assert.ok(second.message.meta.products.length > 0);
      second.message.meta.products.forEach((p) => assert.ok(p.price <= 50000));
    });
  });

  describe('discover deck + reels', () => {
    let swiper;
    let liked;
    let passed;
    let bagged;
    before(async () => {
      swiper = await registerUser();
      liked = await productIn('fragrances');
      passed = await productIn('groceries');
      bagged = await productIn('sunglasses');
    });

    it('DSC-01 guests get a diverse popular deck', async () => {
      const res = await api.get('/api/v1/discover/deck?limit=12').expect(200);
      const d = res.body.data;
      assert.equal(d.personalized, false);
      assert.equal(d.products.length, 12);
      const perCat = d.products.reduce((m, c) => m.set(c.category.slug, (m.get(c.category.slug) || 0) + 1), new Map());
      assert.ok(Math.max(...perCat.values()) <= 3);
      assert.ok(d.products.every((c) => c.inStock && c.match));
    });

    it('DSC-02 swipe validation and auth', async () => {
      await api.post('/api/v1/discover/swipe').send({ productId: liked.id, action: 'like' }).expect(401);
      await api.post('/api/v1/discover/swipe').set(swiper.auth).send({ productId: liked.id, action: 'love' }).expect(400);
      await api.post('/api/v1/discover/swipe').set(swiper.auth).send({ productId: 99999999, action: 'like' }).expect(404);
      await api.get('/api/v1/discover/deck?limit=0').expect(400);
    });

    it('DSC-03 like returns taste + similar "next" cards; pass returns no next', async () => {
      const like = (await api.post('/api/v1/discover/swipe').set(swiper.auth).send({ productId: liked.id, action: 'like' }).expect(200)).body.data;
      assert.equal(like.action, 'like');
      assert.ok(like.next.length > 0 && like.next.length <= 3);
      assert.ok(like.next.every((p) => p.id !== liked.id));
      assert.equal(like.taste.categories[0].slug, 'fragrances');
      assert.ok(like.taste.confidence > 0 && like.taste.confidence <= 1);
      assert.equal(like.taste.priceAppetite.min, liked.price);
      const pass = (await api.post('/api/v1/discover/swipe').set(swiper.auth).send({ productId: passed.id, action: 'pass' }).expect(200)).body.data;
      assert.deepEqual(pass.next, []);
      assert.equal(pass.taste.swipes.passes, 1);
      const row = await db('user_interactions').where({ user_id: swiper.user.id, product_id: passed.id, type: 'pass', source: 'discover' }).first();
      assert.ok(row);
    });

    it('DSC-04 bag adds the item to the cart', async () => {
      await api.post('/api/v1/discover/swipe').set(swiper.auth).send({ productId: bagged.id, action: 'bag' }).expect(200);
      const cart = (await api.get('/api/v1/cart').set(swiper.auth).expect(200)).body.data;
      assert.ok(cart.items.some((i) => i.productId === bagged.id));
    });

    it('DSC-05 the deck excludes swiped items and recommendations drop passed ones', async () => {
      const deck = (await api.get('/api/v1/discover/deck?limit=40').set(swiper.auth).expect(200)).body.data;
      const ids = deck.products.map((c) => c.id);
      [liked.id, passed.id, bagged.id].forEach((id) => assert.ok(!ids.includes(id)));
      assert.ok(deck.excludedRecent >= 3);
      const recs = (await api.get(`${AI}/recommendations?limit=30`).set(swiper.auth).expect(200)).body.data;
      assert.ok(!recs.products.some((p) => p.id === passed.id));
      const taste = (await api.get('/api/v1/discover/taste').set(swiper.auth).expect(200)).body.data;
      assert.ok(taste.topSignals.length >= 1);
    });

    it('DSC-06 reels: one story per department with 5-8 products and a headline', async () => {
      const res = await api.get('/api/v1/discover/reels').expect(200);
      const reels = res.body.data.reels;
      assert.ok(reels.length >= 5);
      reels.forEach((r) => {
        assert.ok(r.products.length >= 5 && r.products.length <= 8, `${r.id} has ${r.products.length}`);
        assert.ok(r.headline && r.subtitle && r.department.slug);
        r.products.forEach((p) => assert.ok(p.inStock));
      });
      await api.get('/api/v1/discover/reels?perDepartment=20').expect(400);
    });
  });

  describe('room scene', () => {
    it('ROOM-01 returns the seven zones with three featured cards each', async () => {
      const res = await api.get('/api/v1/catalog/room').expect(200);
      const zones = res.body.data;
      assert.deepEqual(zones.map((z) => z.id), ['desk', 'wardrobe', 'vanity', 'kitchen', 'shelf', 'corner', 'garage']);
      zones.forEach((z) => {
        assert.equal(z.featured.length, 3);
        assert.ok(z.label && z.department.slug && z.categories.length);
        z.featured.forEach((p) => assert.ok(z.categories.some((c) => c.slug === p.category.slug)));
      });
    });

    it('ROOM-02 personalizes for a signed-in shopper with interests', async () => {
      const u = await registerUser();
      await api.put('/api/v1/users/me/preferences').set(u.auth).send({ interests: ['mens-shirts'], gender: 'men' }).expect(200);
      const zones = (await api.get('/api/v1/catalog/room').set(u.auth).expect(200)).body.data;
      const wardrobe = zones.find((z) => z.id === 'wardrobe');
      assert.equal(wardrobe.personalized, true);
      wardrobe.featured.forEach((p) => assert.ok(!p.category.slug.startsWith('womens-')));
    });
  });

  describe('shopping memory', () => {
    let m;
    let phone;
    before(async () => {
      m = await registerUser();
      phone = await productIn('smartphones');
      await api.get(`/api/v1/products/${phone.id}`).set(m.auth).expect(200);
      await api.post('/api/v1/wishlist').set(m.auth).send({ productId: phone.id }).expect(200);
      const second = await productIn('smartphones', (q) => q.whereNot('p.id', phone.id));
      await api.get(`/api/v1/products/${second.id}`).set(m.auth).expect(200);
      await api.get(`${AI}/search?q=gaming laptop`).set(m.auth).expect(200);
      await api.post(`${AI}/chat`).set(m.auth).send({ message: 'phones under 50k' }).expect(200);
    });

    it('MEM-01 GET shows human-readable memory', async () => {
      const d = (await api.get('/api/v1/users/me/memory').set(m.auth).expect(200)).body.data;
      assert.equal(d.enabled, true);
      assert.equal(d.topCategories[0].slug, 'smartphones');
      assert.ok(d.recentSearches.includes('gaming laptop'));
      assert.ok(d.budgetBand && d.budgetBand.label);
      assert.ok(d.summary.some((s) => /Smartphones/.test(s)));
      assert.ok(d.counts.interactions >= 2);
    });

    it('MEM-02 PUT validates and turns memory off: recommendations stop being personal and nothing new is tracked', async () => {
      await api.put('/api/v1/users/me/memory').set(m.auth).send({ enabled: 'no' }).expect(400);
      const before = (await api.get(`${AI}/recommendations`).set(m.auth).expect(200)).body.data;
      assert.notEqual(before.strategy, 'popularity');
      await api.put('/api/v1/users/me/memory').set(m.auth).send({ enabled: false }).expect(200);
      const after = (await api.get(`${AI}/recommendations`).set(m.auth).expect(200)).body.data;
      assert.equal(after.strategy, 'popularity');
      const count = async () => Number((await db('user_interactions').where({ user_id: m.user.id }).count('* as n').first()).n);
      const n = await count();
      await api.get(`/api/v1/products/${phone.id}`).set(m.auth).expect(200);
      await api.get(`${AI}/search?q=perfume`).set(m.auth).expect(200);
      assert.equal(await count(), n);
      const mem = (await api.get('/api/v1/users/me/memory').set(m.auth).expect(200)).body.data;
      assert.equal(mem.enabled, false);
      assert.ok(!mem.recentSearches.includes('perfume'));
      await api.put('/api/v1/users/me/memory').set(m.auth).send({ enabled: true }).expect(200);
    });

    it('MEM-03 DELETE clears only this user\'s signals, searches and chat context', async () => {
      const otherUser = await registerUser();
      await api.get(`/api/v1/products/${phone.id}`).set(otherUser.auth).expect(200);
      const res = await api.delete('/api/v1/users/me/memory').set(m.auth).expect(200);
      assert.ok(res.body.data.cleared.interactions >= 2);
      assert.ok(res.body.data.cleared.searches >= 1);
      assert.ok(res.body.data.cleared.chatContexts >= 1);
      const d = (await api.get('/api/v1/users/me/memory').set(m.auth).expect(200)).body.data;
      assert.equal(d.counts.interactions, 0);
      assert.equal(d.topCategories.length, 0);
      assert.equal(d.recentSearches.length, 0);
      const wish = (await api.get('/api/v1/wishlist/ids').set(m.auth).expect(200)).body.data;
      assert.ok(wish.includes(phone.id));
      const others = Number((await db('user_interactions').where({ user_id: otherUser.user.id }).count('* as n').first()).n);
      assert.equal(others, 1);
      await api.get('/api/v1/users/me/memory').expect(401);
    });
  });

  describe('voice transcripts and llm stats', () => {
    it('VOI-01 a punctuation-less Roman-Urdu transcript with fillers and spoken numbers', async () => {
      const res = await chat('umm acha yaar mujhe sasta phone chahiye fifty thousand tak');
      const meta = res.message.meta;
      assert.equal(meta.entities.category, 'smartphones');
      assert.equal(meta.entities.budget.max, 50000);
      assert.equal(meta.entities.recipient, null);
      meta.products.forEach((p) => assert.ok(p.price <= 50000));
      assert.ok(!/yaar|umm/.test(meta.nlu.normalized));
    });

    it('VOI-02 "bhai ke liye perfume" keeps the recipient', async () => {
      const res = await chat('bhai ke liye perfume do hazar tak');
      assert.equal(res.message.meta.entities.recipient, 'brother');
      assert.equal(res.message.meta.entities.budget.max, 2000);
    });

    it('LLM-01 /ai/insights reports llm usage and limits', async () => {
      const d = (await api.get(`${AI}/insights`).expect(200)).body.data.llm;
      assert.equal(d.provider, 'none');
      assert.equal(typeof d.usedToday, 'number');
      assert.equal(typeof d.dailyLimit, 'number');
      assert.equal(typeof d.cacheHits, 'number');
      assert.ok(['closed', 'open', 'half-open'].includes(d.circuit));
    });
  });
});
