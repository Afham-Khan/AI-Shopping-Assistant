const assert = require('node:assert/strict');
const { api, db, registerUser, bearer } = require('./helpers');

const AI = '/api/v1/ai';
let n = 0;
const aiUser = (overrides = {}) => {
  n += 1;
  return registerUser({ email: `test+ai${Date.now()}${n}@cartwise.test`, ...overrides });
};

// integration tests need the migrated + seeded database
const dbReady = async () => {
  try {
    const row = await db('products').count('* as c').first();
    return Number(row.c) > 0;
  } catch {
    return false;
  }
};

const isRecommended = (p) => {
  assert.ok(Number.isInteger(p.id));
  assert.equal(typeof p.title, 'string');
  assert.equal(typeof p.price, 'number');
  assert.ok(p.match && typeof p.match.score === 'number');
  assert.ok(Array.isArray(p.match.reasons) && p.match.reasons.length > 0);
};

describe('AI API (integration)', function aiApi() {
  this.timeout(60000);
  let session;

  before(async function setup() {
    if (!(await dbReady())) return this.skip();
    // build the indexes up front so latency checks measure warm turns
    await require('../api/modules/ai/engine').warmup();
    session = await aiUser();
    return null;
  });

  describe('chat', () => {
    let conversationId;
    let shown = [];

    it('API-01 requires auth', async () => {
      await api.post(`${AI}/chat`).send({ message: 'hi' }).expect(401);
    });

    it('API-02 validates the message', async () => {
      await api.post(`${AI}/chat`).set(session.auth).send({ message: '' }).expect(400);
      await api.post(`${AI}/chat`).set(session.auth).send({ message: 'x'.repeat(501) }).expect(400);
      await api.post(`${AI}/chat`).set(session.auth).send({ message: 'hi', conversationId: 99999999 }).expect(404);
    });

    it('API-03 search turn respects the budget and explains picks', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'show me smartphones under 100k' }).expect(200);
      const { data } = res.body;
      conversationId = data.conversationId;
      assert.ok(conversationId);
      assert.equal(data.userMessage.role, 'user');
      const { meta } = data.message;
      assert.ok(['product_search', 'budget_query'].includes(meta.intent));
      assert.equal(meta.entities.category, 'smartphones');
      assert.equal(meta.entities.budget.max, 100000);
      assert.ok(meta.products.length >= 2 && meta.products.length <= 6);
      meta.products.forEach((p) => {
        isRecommended(p);
        assert.ok(p.price <= 100000);
        assert.equal(p.category.slug, 'smartphones');
      });
      assert.ok(meta.suggestions.length >= 2 && meta.suggestions.length <= 4);
      assert.equal(meta.source, 'local');
      assert.ok(meta.latencyMs < 3000);
      assert.match(data.message.content, /\*\*Rs [\d,]+\*\*/);
      shown = meta.products;
    });

    it('API-04 "cheaper" lowers prices and keeps the category', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'cheaper', conversationId }).expect(200);
      const { meta } = res.body.data.message;
      assert.equal(meta.intent, 'refine_cheaper');
      const prevMedian = shown.map((p) => p.price).sort((a, b) => a - b)[Math.floor(shown.length / 2)];
      assert.ok(meta.products.length >= 1);
      meta.products.forEach((p) => {
        assert.ok(p.price < prevMedian);
        assert.equal(p.category.slug, 'smartphones');
      });
      shown = meta.products;
    });

    it('API-05 "compare the first two" compares shown products', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'compare the first two', conversationId }).expect(200);
      const { meta } = res.body.data.message;
      assert.equal(meta.intent, 'compare');
      assert.equal(meta.comparison.products.length, 2);
      assert.ok(meta.comparison.rows.some((r) => r.label === 'Price'));
      assert.ok(meta.comparison.verdict.picks.some((p) => p.label === 'Best value'));
      assert.ok(meta.comparison.verdict.summary.length > 20);
    });

    it('API-06 "add the second one to my cart" returns an add_to_cart action', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'add the second one to my cart', conversationId }).expect(200);
      const { meta } = res.body.data.message;
      assert.equal(meta.intent, 'add_to_cart');
      const action = meta.actions.find((a) => a.type === 'add_to_cart');
      assert.ok(action);
      const expected = shown.length >= 2 ? shown[1].id : null;
      if (expected) assert.equal(action.productId, expected);
      assert.equal(action.quantity, 1);
    });

    it('API-07 vague gift request triggers slot-filling clarifications', async () => {
      const first = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'I need a gift' }).expect(200);
      const giftConv = first.body.data.conversationId;
      const m1 = first.body.data.message.meta;
      assert.equal(m1.intent, 'gift_suggestion');
      assert.ok(m1.clarify && m1.clarify.options.includes('Mom'));
      assert.equal(m1.products.length, 0);

      const second = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'Mom', conversationId: giftConv }).expect(200);
      const m2 = second.body.data.message.meta;
      assert.ok(m2.clarify && /budget/i.test(m2.clarify.question));

      const third = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'Under Rs 15,000', conversationId: giftConv }).expect(200);
      const m3 = third.body.data.message.meta;
      assert.equal(m3.intent, 'gift_suggestion');
      assert.ok(m3.products.length > 0);
      m3.products.forEach((p) => assert.ok(p.price <= 15000));
      assert.equal(m3.clarify, null);
    });

    it('API-08 order status for a user without orders', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'where is my order' }).expect(200);
      assert.equal(res.body.data.message.meta.intent, 'order_status');
      assert.match(res.body.data.message.content, /haven't placed any orders/);
    });

    it('API-09 conversations list, detail and delete', async () => {
      const list = await api.get(`${AI}/conversations`).set(session.auth).expect(200);
      const conv = list.body.data.find((c) => c.id === conversationId);
      assert.ok(conv);
      assert.notEqual(conv.title, 'New chat');
      assert.ok(conv.lastMessage);
      const detail = await api.get(`${AI}/conversations/${conversationId}`).set(session.auth).expect(200);
      assert.ok(detail.body.data.messages.length >= 8);
      const assistant = detail.body.data.messages.find((m) => m.role === 'assistant');
      assert.ok(assistant.meta.intent);
      const other = await aiUser();
      await api.get(`${AI}/conversations/${conversationId}`).set(other.auth).expect(404);
      await api.delete(`${AI}/conversations/${conversationId}`).set(session.auth).expect(200);
      await api.get(`${AI}/conversations/${conversationId}`).set(session.auth).expect(404);
    });

    it('API-10 feedback on assistant messages', async () => {
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'hello' }).expect(200);
      const { message, userMessage } = res.body.data;
      await api.post(`${AI}/messages/${message.id}/feedback`).set(session.auth).send({ rating: 1 }).expect(200);
      await api.post(`${AI}/messages/${message.id}/feedback`).set(session.auth).send({ rating: -1 }).expect(200);
      await api.post(`${AI}/messages/${message.id}/feedback`).set(session.auth).send({ rating: 5 }).expect(400);
      await api.post(`${AI}/messages/${userMessage.id}/feedback`).set(session.auth).send({ rating: 1 }).expect(400);
      const row = await db('ai_feedback').where({ message_id: message.id }).first();
      assert.equal(row.rating, -1);
    });
  });

  describe('recommendations', () => {
    let productId;
    before(async () => {
      productId = (await db('products').where('category_id', db('categories').select('id').where({ slug: 'smartphones' }).first()).first('id')).id;
    });

    it('API-11 guests get trending, users with interests get personalized picks', async () => {
      const guest = await api.get(`${AI}/recommendations?limit=6`).expect(200);
      assert.equal(guest.body.data.title, 'Trending now');
      assert.equal(guest.body.data.products.length, 6);
      guest.body.data.products.forEach(isRecommended);

      const user = await aiUser();
      await api.put('/api/v1/users/me/preferences').set(user.auth).send({ interests: ['laptops', 'smartphones'], budget: { min: 0, max: 500000 }, gender: 'men' }).expect(200);
      const res = await api.get(`${AI}/recommendations?limit=8`).set(user.auth).expect(200);
      assert.match(res.body.data.title, /Picked for you/);
      const cats = res.body.data.products.map((p) => p.category.slug);
      assert.ok(cats.filter((c) => c === 'laptops' || c === 'smartphones').length >= 3);
    });

    it('API-12 similar products exclude the product itself', async () => {
      const res = await api.get(`${AI}/similar/${productId}?limit=5`).expect(200);
      assert.equal(res.body.data.length, 5);
      assert.ok(res.body.data.every((p) => p.id !== productId));
      res.body.data.forEach(isRecommended);
      await api.get(`${AI}/similar/99999999`).expect(404);
    });

    it('API-13 bought together returns complementary items', async () => {
      const res = await api.get(`${AI}/bought-together/${productId}?limit=4`).expect(200);
      assert.ok(res.body.data.length > 0);
      res.body.data.forEach(isRecommended);
    });

    it('API-14 review summary', async () => {
      const reviewed = await db('reviews').groupBy('product_id').select('product_id').count('* as c').orderBy('c', 'desc').first();
      const res = await api.get(`${AI}/review-summary/${reviewed.product_id}`).expect(200);
      const s = res.body.data;
      assert.ok(s.reviewCount > 0);
      assert.ok(['Very positive', 'Positive', 'Mixed', 'Negative'].includes(s.sentiment.label));
      assert.ok(Array.isArray(s.pros) && Array.isArray(s.cons));
      assert.ok(s.summary.length > 20);
      await api.get(`${AI}/review-summary/99999999`).expect(404);
    });

    it('API-15 compare endpoint', async () => {
      const ids = (await db('products').orderBy('id').limit(3).select('id')).map((r) => r.id);
      const res = await api.post(`${AI}/compare`).send({ productIds: ids }).expect(200);
      assert.equal(res.body.data.products.length, 3);
      assert.ok(res.body.data.products[0].images);
      assert.equal(res.body.data.verdict.picks[0].label, 'Best value');
      await api.post(`${AI}/compare`).send({ productIds: [ids[0]] }).expect(400);
    });
  });

  describe('smart search, finder, nlu, insights', () => {
    it('API-16 natural-language search with chips and history', async () => {
      const res = await api.get(`${AI}/search`).query({ q: 'red running shoes for women under 15k' }).set(session.auth).expect(200);
      const { data } = res.body;
      assert.ok(data.interpretation.chips.some((c) => c.type === 'budget'));
      assert.ok(data.interpretation.chips.some((c) => c.type === 'gender'));
      assert.ok(data.products.length > 0);
      data.products.forEach((p) => assert.ok(p.price <= 15000));
      const history = await db('search_history').where({ user_id: session.user.id }).first();
      assert.ok(history);
    });

    it('API-17 relaxed constraints are flagged', async () => {
      const res = await api.get(`${AI}/search`).query({ q: 'smartphones under 1000' }).expect(200);
      assert.equal(res.body.data.fallback, true);
      assert.match(res.body.data.interpretation.text, /closest options start at/);
      assert.ok(res.body.data.products.length > 0);
    });

    it('API-18 finder flows and results', async () => {
      const flows = await api.get(`${AI}/finder`).expect(200);
      assert.ok(flows.body.data.length >= 6);
      const electronics = flows.body.data.find((f) => f.key === 'electronics');
      const budgetQ = electronics.questions.find((q) => q.type === 'budget');
      assert.ok(budgetQ.options.length >= 3);
      const res = await api.post(`${AI}/finder`).send({ department: electronics.slug, answers: { type: 'laptops', use: ['work'], budget: 'any', brand: 'any' } }).expect(200);
      assert.ok(res.body.data.products.length > 0);
      assert.ok(res.body.data.products.every((p) => p.category.slug === 'laptops'));
      assert.match(res.body.data.summary, /Based on your answers/);
      await api.post(`${AI}/finder`).send({ department: 'nope' }).expect(400);
    });

    it('API-19 nlu playground', async () => {
      const res = await api.post(`${AI}/nlu`).send({ text: 'sasta samsng mobile chahiye 30k tak' }).expect(200);
      const d = res.body.data;
      assert.ok(d.intent && d.confidence > 0);
      assert.ok(Array.isArray(d.alternatives));
      assert.equal(d.entities.budget.max, 30000);
      assert.deepEqual(d.entities.brands, ['samsung']);
      assert.ok(d.tokens.length > 3);
      assert.equal(typeof d.latencyMs, 'number');
      await api.post(`${AI}/nlu`).send({}).expect(400);
    });

    it('API-20 insights expose model metrics and stats', async () => {
      const res = await api.get(`${AI}/insights`).expect(200);
      const d = res.body.data;
      assert.ok(d.intentModel.testAccuracy >= 0.9);
      assert.ok(d.intentModel.classes.length >= 15);
      assert.ok(['neural', 'tfidf'].includes(d.embeddings.mode));
      assert.ok(d.embeddings.indexedProducts > 0);
      assert.ok('enabled' in d.llm);
      assert.ok(d.recommender.signals.length > 3);
      assert.ok(d.stats.conversations >= 1);
      assert.ok(d.stats.positiveFeedbackRate === null || d.stats.positiveFeedbackRate >= 0);
    });

    it('API-21 invalid tokens are rejected on chat', async () => {
      await api.post(`${AI}/chat`).set(bearer('nope')).send({ message: 'hi' }).expect(401);
    });
  });
});
