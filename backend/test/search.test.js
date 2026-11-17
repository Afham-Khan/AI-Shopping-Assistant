const assert = require('node:assert/strict');
const { api, registerUser } = require('./helpers');

const SEARCH = '/api/v1/search';

describe('Search', () => {
  it('SRC-01 suggests products for a prefix', async () => {
    const res = await api.get(`${SEARCH}/suggestions?q=iph`);
    assert.equal(res.status, 200);
    const { products, categories, queries } = res.body.data;
    assert.ok(products.length > 0 && products.length <= 6);
    assert.ok(products.some((p) => /iphone/i.test(p.title)));
    assert.deepEqual(Object.keys(products[0]).sort(), ['id', 'price', 'thumbnail', 'title']);
    assert.ok(Array.isArray(categories) && Array.isArray(queries));
  });

  it('SRC-08 title-prefix matches rank before keyword matches', async () => {
    const res = await api.get(`${SEARCH}/suggestions?q=sam`);
    const flags = res.body.data.products.map((p) => /^sam/i.test(p.title));
    assert.ok(flags[0]);
    assert.ok(flags.every((f, i) => i === 0 || f <= flags[i - 1]), 'prefix matches must come first');
  });

  it('SRC-02 suggests categories', async () => {
    const res = await api.get(`${SEARCH}/suggestions?q=lap`);
    assert.ok(res.body.data.categories.some((c) => c.slug === 'laptops'));
  });

  it('SRC-03 requires q', async () => {
    assert.equal((await api.get(`${SEARCH}/suggestions`)).status, 400);
    assert.equal((await api.get(`${SEARCH}/suggestions?q=`)).status, 400);
  });

  it('SRC-04 returns trending queries', async () => {
    const res = await api.get(`${SEARCH}/trending`);
    assert.equal(res.status, 200);
    assert.ok(res.body.data.length > 0);
    assert.ok(res.body.data.every((q) => typeof q === 'string'));
  });

  describe('history', () => {
    let session;
    before(async () => { session = await registerUser(); });

    it('SRC-05 requires auth', async () => {
      assert.equal((await api.get(`${SEARCH}/history`)).status, 401);
      assert.equal((await api.post(`${SEARCH}/history`).send({ query: 'x' })).status, 401);
    });

    it('SRC-06 stores distinct queries, latest first', async () => {
      await api.post(`${SEARCH}/history`).set(session.auth).send({ query: 'Gaming Laptop', resultsCount: 5 }).expect(201);
      await api.post(`${SEARCH}/history`).set(session.auth).send({ query: 'red dress', resultsCount: 3 }).expect(201);
      await api.post(`${SEARCH}/history`).set(session.auth).send({ query: 'gaming laptop', resultsCount: 5 }).expect(201);
      assert.equal((await api.post(`${SEARCH}/history`).set(session.auth).send({ query: '' })).status, 400);
      const res = await api.get(`${SEARCH}/history`).set(session.auth);
      assert.deepEqual(res.body.data.map((h) => h.query), ['gaming laptop', 'red dress']);
      assert.ok(res.body.data[0].createdAt);
    });

    it('SRC-07 clears history', async () => {
      await api.delete(`${SEARCH}/history`).set(session.auth).expect(200);
      const res = await api.get(`${SEARCH}/history`).set(session.auth);
      assert.deepEqual(res.body.data, []);
    });
  });
});
