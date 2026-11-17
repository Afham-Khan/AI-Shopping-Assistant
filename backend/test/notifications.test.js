const assert = require('node:assert/strict');
const { api, db, registerUser, addAddress, findProduct } = require('./helpers');

const NOTES = '/api/v1/notifications';

describe('Notifications', () => {
  let session;
  let stranger;
  let first;

  before(async () => {
    [session, stranger] = await Promise.all([registerUser(), registerUser()]);
    const address = await addAddress(session.auth);
    const product = await findProduct((q) => q.where('stock', '>=', 20).orderBy('price').offset(3));
    await api.post('/api/v1/cart/items').set(session.auth).send({ productId: product.id }).expect(200);
    const order = (await api.post('/api/v1/orders').set(session.auth).send({ addressId: address.id, paymentMethod: 'cod' }).expect(201)).body.data;
    await api.post(`/api/v1/orders/${order.id}/cancel`).set(session.auth).expect(200);
  });

  it('NTF-01 lists notifications with unread count', async () => {
    const res = await api.get(NOTES).set(session.auth);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.length, 2);
    assert.equal(res.body.meta.unreadCount, 2);
    first = res.body.data[0];
    assert.equal(first.type, 'order');
    assert.equal(first.readAt, null);
    assert.ok(first.data.orderNumber);
    assert.deepEqual(res.body.data.map((n) => n.title), ['Order cancelled', 'Order placed']);
  });

  it('NTF-02 marks one as read', async () => {
    await api.post(`${NOTES}/${first.id}/read`).set(session.auth).expect(200);
    const res = await api.get(`${NOTES}/unread-count`).set(session.auth);
    assert.deepEqual(res.body.data, { count: 1 });
    const row = await db('notifications').where({ id: first.id }).first();
    assert.ok(row.read_at);
  });

  it("NTF-03 cannot read someone else's notification", async () => {
    assert.equal((await api.post(`${NOTES}/${first.id}/read`).set(stranger.auth)).status, 404);
    assert.equal((await api.post(`${NOTES}/abc/read`).set(session.auth)).status, 400);
    assert.equal((await api.get(NOTES)).status, 401);
  });

  it('NTF-04 marks all as read', async () => {
    await api.post(`${NOTES}/read-all`).set(session.auth).expect(200);
    assert.equal((await api.get(`${NOTES}/unread-count`).set(session.auth)).body.data.count, 0);
  });
});
