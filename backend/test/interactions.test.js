const assert = require('node:assert/strict');
const { api, db, registerUser } = require('./helpers');

const INTERACTIONS = '/api/v1/interactions';

describe('Interactions', () => {
  let session;
  let product;
  before(async () => {
    session = await registerUser();
    product = await db('products').orderBy('id').first('id');
  });

  it('INT-01 ignores guests', async () => {
    const before = await db('user_interactions').count('* as n').first();
    const res = await api.post(INTERACTIONS).send({ productId: product.id, type: 'click' });
    assert.equal(res.status, 200);
    assert.equal(res.body.data, null);
    assert.equal((await db('user_interactions').count('* as n').first()).n, before.n);
  });

  it('INT-02 stores signals for signed-in users', async () => {
    const res = await api.post(INTERACTIONS).set(session.auth).send({ productId: product.id, type: 'ai_click', source: 'chat' });
    assert.equal(res.status, 200);
    const row = await db('user_interactions').where({ user_id: session.user.id }).first();
    assert.equal(row.type, 'ai_click');
    assert.equal(row.source, 'chat');
  });

  it('INT-03 validates type and product', async () => {
    assert.equal((await api.post(INTERACTIONS).set(session.auth).send({ productId: product.id, type: 'purchase' })).status, 400);
    assert.equal((await api.post(INTERACTIONS).set(session.auth).send({ productId: 0, type: 'view' })).status, 400);
    assert.equal((await api.post(INTERACTIONS).set(session.auth).send({ productId: 999999, type: 'view' })).status, 404);
  });
});
