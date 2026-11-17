const assert = require('node:assert/strict');
const { api, db, registerUser } = require('./helpers');

const WISH = '/api/v1/wishlist';

describe('Wishlist', () => {
  let session;
  let product;
  before(async () => {
    session = await registerUser();
    product = await db('products').where('external_id', 160).first();
  });

  it('WSH-01 adds a product', async () => {
    const res = await api.post(WISH).set(session.auth).send({ productId: product.id });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, { productId: product.id });
    assert.deepEqual((await api.get(`${WISH}/ids`).set(session.auth)).body.data, [product.id]);
    const list = (await api.get(WISH).set(session.auth)).body.data;
    assert.equal(list[0].id, product.id);
    assert.ok(list[0].addedAt);
  });

  it('WSH-02 adding twice is idempotent', async () => {
    const res = await api.post(WISH).set(session.auth).send({ productId: product.id });
    assert.equal(res.status, 200);
    assert.equal((await api.get(`${WISH}/ids`).set(session.auth)).body.data.length, 1);
    const signals = await db('user_interactions').where({ user_id: session.user.id, type: 'wishlist' }).count('* as n').first();
    assert.equal(signals.n, 1);
  });

  it('WSH-03 removes a product', async () => {
    assert.equal((await api.delete(`${WISH}/${product.id}`).set(session.auth)).status, 200);
    assert.deepEqual((await api.get(`${WISH}/ids`).set(session.auth)).body.data, []);
  });

  it('WSH-04 handles bad input and auth', async () => {
    assert.equal((await api.post(WISH).set(session.auth).send({ productId: 999999 })).status, 404);
    assert.equal((await api.post(WISH).set(session.auth).send({ productId: 'abc' })).status, 400);
    assert.equal((await api.delete(`${WISH}/-1`).set(session.auth)).status, 400);
    assert.equal((await api.get(WISH)).status, 401);
  });
});
